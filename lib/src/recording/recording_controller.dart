import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../schedule/schedule_models.dart';
import '../schedule/schedule_repository.dart';
import 'recording_socket.dart';

typedef Json = Map<String, dynamic>;

String recordingUUID(String value) {
  final hash = sha256.convert(utf8.encode(value)).toString();
  return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-5${hash.substring(13, 16)}-a${hash.substring(17, 20)}-${hash.substring(20, 32)}';
}

class RecordingSlot {
  RecordingSlot(
    this.courseId,
    this.start,
    this.end,
    this.startUnit,
    this.endUnit,
  );
  final String courseId;
  final DateTime start;
  DateTime end;
  final int startUnit;
  int endUnit;
  Json toJson() => {
    'id': recordingUUID('$courseId|${start.toIso8601String()}'),
    'course_id': courseId,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'start_ms': start.millisecondsSinceEpoch,
    'end_ms': end.millisecondsSinceEpoch,
  };
}

List<RecordingSlot> mergeRecordingSlots(
  List<RecordingSlot> slots,
  int gapMinutes,
) {
  final sorted = [...slots]..sort((a, b) => a.start.compareTo(b.start));
  final result = <RecordingSlot>[];
  for (final slot in sorted) {
    final previous = result.lastOrNull;
    if (previous != null &&
        previous.courseId == slot.courseId &&
        previous.endUnit + 1 == slot.startUnit &&
        previous.start.year == slot.start.year &&
        previous.start.month == slot.start.month &&
        previous.start.day == slot.start.day &&
        !slot.start.isBefore(previous.end) &&
        slot.start.difference(previous.end).inMinutes <= gapMinutes) {
      previous.end = slot.end;
      previous.endUnit = slot.endUnit;
    } else {
      result.add(
        RecordingSlot(
          slot.courseId,
          slot.start,
          slot.end,
          slot.startUnit,
          slot.endUnit,
        ),
      );
    }
  }
  return result;
}

class RecordingController extends ChangeNotifier with WidgetsBindingObserver {
  RecordingController._();
  @visibleForTesting
  RecordingController.forTesting();
  static final instance = RecordingController._();
  static const native = MethodChannel('blackbook/recording');
  static const events = EventChannel('blackbook/recording/events');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool enabled = false;
  bool autoRecord = false;
  String baseUrl = '';
  String apiKey = '';
  int mergeGap = 30;
  String activeSemester = '';
  Json status = {};
  String? error;
  List<Json> courses = [];
  List<Json> transcript = [];
  List<Json> localRecordings = [];
  Timer? _localTimer;
  Timer? _scheduleRetry;
  bool _readingLocal = false;
  bool _nativeUpgradeRequired = false;
  List<RecordingSlot> slots = [];
  List<ScheduleBundle> semesters = [];
  StreamSubscription<dynamic>? _nativeSub;
  StreamSubscription<String>? _socket;
  Timer? _reconnect;
  Timer? _healthTimer;
  bool streamConnected = false;
  String? streamError;
  Json? liveTask;
  int _connectionGeneration = 0;
  bool _checkingHealth = false;
  Future<void>? _loading;
  String _streamId = '';
  int _cursor = 0;
  bool _syncing = false;
  bool _syncAgain = false;
  bool get recording => status['recording'] == true;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('recording.enabled') ?? false;
    autoRecord = p.getBool('recording.auto') ?? false;
    baseUrl = p.getString('recording.url') ?? '';
    apiKey = p.getString('recording.key') ?? '';
    mergeGap = p.getInt('recording.gap') ?? 30;
    activeSemester = p.getString('recording.semester') ?? '';
    courses = (jsonDecode(p.getString('recording.courses') ?? '[]') as List)
        .map((e) => Json.from(e as Map))
        .toList();
    if (supported) {
      WidgetsBinding.instance.addObserver(this);
      await refreshLocalRecordings();
      _localTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(refreshLocalRecordings()),
      );
      _scheduleRetry = Timer.periodic(const Duration(seconds: 30), (_) {
        if (enabled && localRecordings.any((r) => r['uploaded'] != true)) {
          unawaited(syncSchedule().catchError((Object _) {}));
        }
      });
      _nativeSub = events.receiveBroadcastStream().listen(
        (event) {
          status = Map<String, dynamic>.from(
            jsonDecode(event as String) as Map,
          );
          final id = status['id'] as String? ?? '';
          if (id != _streamId) {
            _streamId = id;
            _cursor = 0;
            transcript = [];
            liveTask = null;
            streamError = null;
            _healthTimer?.cancel();
            _connect();
            if (id.isNotEmpty) {
              _healthTimer = Timer.periodic(
                const Duration(seconds: 5),
                (_) => _checkLiveHealth(),
              );
            }
          }
          notifyListeners();
        },
        onError: (Object e) {
          error = '$e';
          notifyListeners();
        },
      );
    }
    notifyListeners();
    if (enabled) {
      await resumeUploads();
      try {
        await syncSchedule();
      } catch (e) {
        error = '$e';
        notifyListeners();
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await saveLocal();
    if (value) {
      try {
        await syncSchedule();
      } catch (e) {
        error = '$e';
      }
    }
    notifyListeners();
  }

  Future<void> saveLocal() async {
    baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (baseUrl.isNotEmpty) {
      final uri = Uri.tryParse(baseUrl);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw ArgumentError('请输入有效的 http(s) 后端地址');
      }
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('recording.enabled', enabled);
    await p.setBool('recording.auto', autoRecord);
    await p.setString(
      'recording.url',
      baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
    );
    await p.setString('recording.key', apiKey);
    await p.setInt('recording.gap', mergeGap);
    await p.setString('recording.semester', activeSemester);
    await _configure();
    await resumeUploads();
    _connect();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(resumeUploads());
  }

  Future<void> refreshLocalRecordings() async {
    if (!supported || _readingLocal || _nativeUpgradeRequired) return;
    _readingLocal = true;
    try {
      final text = await native.invokeMethod<String>('localRecordings');
      localRecordings = (jsonDecode(text ?? '[]') as List)
          .map((r) => Json.from(r as Map))
          .toList();
      notifyListeners();
    } on PlatformException catch (e) {
      if (e.message?.contains('未知录音命令') == true) {
        _nativeUpgradeRequired = true;
        error = '录音原生组件版本过旧：请停止调试后重新 flutter run，或覆盖安装新版 APK。热重载无效，请勿卸载或清除数据。';
        notifyListeners();
      } else {
        error = '读取本机录音失败：${e.message ?? e.code}';
      }
    } catch (e) {
      error = '读取本机录音失败：$e';
    } finally {
      _readingLocal = false;
    }
  }

  Future<void> resumeUploads() async {
    if (!supported || !enabled) return;
    await refreshLocalRecordings();
    if (!localRecordings.any((r) => r['uploaded'] != true)) return;
    try {
      await command('sync');
    } catch (e) {
      error = '自动恢复上传失败，可点立即上传重试：$e';
      notifyListeners();
    }
  }

  Future<void> uploadRecording(String id) async {
    await command('retryUpload', {'recording_id': id});
    await refreshLocalRecordings();
  }

  String _recordingCacheKey(String course) =>
      'recording.remote.${recordingUUID(baseUrl)}.$course';
  Future<List<Json>> cachedRecordings(String course) async {
    final p = await SharedPreferences.getInstance();
    return (jsonDecode(p.getString(_recordingCacheKey(course)) ?? '[]') as List)
        .map((r) => Json.from(r as Map))
        .toList();
  }

  Future<List<Json>> fetchRecordings(String course) async {
    final rows =
        (await api(
                      'GET',
                      '/recordings?course_id=${Uri.encodeQueryComponent(course)}',
                    )
                    as List? ??
                [])
            .map((r) => Json.from(r as Map))
            .toList();
    final p = await SharedPreferences.getInstance();
    await p.setString(_recordingCacheKey(course), jsonEncode(rows));
    return rows;
  }

  Future<void> _configure() async {
    if (!supported) return;
    await native.invokeMethod('configure', {
      'json': jsonEncode({
        'enabled': enabled,
        'auto_record': autoRecord,
        'base_url': baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        'api_key': apiKey,
        'occurrences': slots.map((s) => s.toJson()).toList(),
      }),
    });
  }

  Future<dynamic> api(String method, String path, [Object? body]) async {
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      throw StateError('请先配置后端地址和 API key');
    }
    final request = http.Request(
      method,
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1$path'),
    );
    request.headers.addAll({
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 30)),
    );
    final data = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data is Map
            ? '${data['error'] ?? data}'
            : 'HTTP ${response.statusCode}',
      );
    }
    return data;
  }

  Future<void> refreshCourses() async {
    courses = ((await api('GET', '/courses')) as List? ?? [])
        .map((e) => Json.from(e as Map))
        .toList();
    final p = await SharedPreferences.getInstance();
    await p.setString('recording.courses', jsonEncode(courses));
    notifyListeners();
  }

  String courseId(ScheduleBundle bundle, CourseActivity a) => recordingUUID(
    '${bundle.semester.id}|${a.programType.name}|${a.lessonId}|${a.courseCode}',
  );

  Future<Json> updateCourse(String id, Json values) async {
    final result = Json.from(await api('PATCH', '/courses/$id', values) as Map);
    if (values.containsKey('name') || values.containsKey('teachers')) {
      const store = ImportedScheduleStore();
      final selected = await store.selectedSemesterId();
      for (final bundle in await store.loadAll()) {
        if (!bundle.schedule.activities.any((a) => courseId(bundle, a) == id)) {
          continue;
        }
        final activities = bundle.schedule.activities.map((a) {
          if (courseId(bundle, a) != id) return a;
          return a.copyWith(
            courseName: values['name'] as String?,
            teachers: (values['teachers'] as String?)?.split('、'),
          );
        }).toList();
        await store.saveBundle(
          bundle.copyWith(
            schedule: bundle.schedule.copyWith(activities: activities),
          ),
          selectAfterSave: selected == bundle.semester.id,
        );
      }
    }
    await syncSchedule();
    return result;
  }

  Future<void> syncSchedule() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      const store = ImportedScheduleStore();
      semesters = await store.loadAll();
      final today = DateTime.now();
      final current = semesters
          .where(
            (b) =>
                !today.isBefore(b.semester.startDate) &&
                today.isBefore(b.semester.endDate.add(const Duration(days: 1))),
          )
          .toList();
      ScheduleBundle? selected;
      if (activeSemester.isNotEmpty) {
        selected = current
            .where((b) => '${b.semester.id}' == activeSemester)
            .firstOrNull;
      } else if (current.length == 1) {
        selected = current.single;
      }
      final all = <String, List<RecordingSlot>>{};
      final syncPayloads = <Json>[];
      for (final bundle in semesters) {
        final choices = await store.loadConflictChoices(bundle.semester.id);
        final occurrences = <RecordingSlot>[];
        final courseMap = <String, Json>{};
        for (final a in bundle.schedule.activities) {
          final id = courseId(bundle, a);
          courseMap[id] = {
            'id': id,
            'name': a.courseName,
            'teachers': a.teachers.join('、'),
            'semester_id': '${bundle.semester.id}',
          };
        }
        for (var week = 1; week <= bundle.semester.totalWeeks; week++) {
          final activities = bundle.schedule.activitiesForWeek(week)
            ..sort(CourseActivity.compareByTime);
          final groups = <List<CourseActivity>>[];
          for (final a in activities) {
            final last = groups.lastOrNull;
            if (last != null &&
                last.first.weekday == a.weekday &&
                last.any(
                  (b) => b.startUnit <= a.endUnit && a.startUnit <= b.endUnit,
                )) {
              last.add(a);
            } else {
              groups.add([a]);
            }
          }
          for (final group in groups) {
            CourseActivity? a;
            if (group.length == 1) {
              a = group.single;
            } else {
              String choiceKey(CourseActivity v) => [
                v.lessonId,
                v.lessonCode,
                v.courseCode,
                v.weekday,
                v.startUnit,
                v.endUnit,
                v.room,
                v.teacherText,
              ].join('#');
              final keys = group.map(choiceKey).toList()..sort();
              final chosen = choices['$week.${keys.join('|')}'];
              a = group.where((v) => choiceKey(v) == chosen).firstOrNull;
              if (a == null) {
                error = '部分课程冲突尚未选择，已跳过自动录音';
                continue;
              }
            }
            final date = bundle.semester.dateFor(
              weekIndex: week,
              weekday: a.weekday,
            );
            if (date.isBefore(bundle.semester.startDate) ||
                date.isAfter(bundle.semester.endDate)) {
              continue;
            }
            DateTime clock(String text) {
              final p = text.split(':');
              return DateTime(
                date.year,
                date.month,
                date.day,
                int.parse(p[0]),
                int.parse(p[1]),
              );
            }

            occurrences.add(
              RecordingSlot(
                courseId(bundle, a),
                clock(a.startTime),
                clock(a.endTime),
                a.startUnit,
                a.endUnit,
              ),
            );
          }
        }
        final merged = mergeRecordingSlots(occurrences, mergeGap);
        // Keep imported courses available before the first successful server connection.
        for (final course in courseMap.values) {
          if (!courses.any((r) => (r['course'] as Map)['id'] == course['id'])) {
            courses.add({
              'course': {...course, 'auto_record': true},
              'recording_count': 0,
              'duration_seconds': 0,
            });
          }
        }
        all['${bundle.semester.id}'] = merged;
        if (baseUrl.isNotEmpty && apiKey.isNotEmpty) {
          syncPayloads.add({
            'semester': {
              'id': '${bundle.semester.id}',
              'name': bundle.semester.name,
              'start': bundle.semester.startDate.toIso8601String(),
              'end': bundle.semester.endDate.toIso8601String(),
            },
            'courses': courseMap.values.toList(),
            'occurrences': merged.map((s) => s.toJson()).toList(),
          });
        }
      }
      void updateSlots() {
        final disabled = courses
            .where((r) => (r['course'] as Map)['auto_record'] != true)
            .map((r) => (r['course'] as Map)['id'])
            .toSet();
        final known = courses.map((r) => (r['course'] as Map)['id']).toSet();
        slots = [];
        for (final entry in all.entries) {
          if (activeSemester.isNotEmpty && entry.key != activeSemester) {
            continue;
          }
          for (final slot in entry.value) {
            final overlapping = semesters
                .where(
                  (b) =>
                      !slot.start.isBefore(b.semester.startDate) &&
                      slot.start.isBefore(
                        b.semester.endDate.add(const Duration(days: 1)),
                      ),
                )
                .length;
            if ((activeSemester.isNotEmpty || overlapping == 1) &&
                !disabled.contains(slot.courseId) &&
                (known.isEmpty || known.contains(slot.courseId))) {
              slots.add(slot);
            }
          }
        }
        slots.sort((a, b) => a.start.compareTo(b.start));
      }

      updateSlots();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('recording.courses', jsonEncode(courses));
      if (current.length > 1 && selected == null) {
        error = '当前有多个学期，请在录音设置指定自动录音学期';
      }
      await _configure();
      notifyListeners();
      // Native scheduling is updated even when the server is offline.
      for (final payload in syncPayloads) {
        await api('POST', '/schedule/sync', payload);
      }
      if (baseUrl.isNotEmpty && apiKey.isNotEmpty) {
        await refreshCourses();
        updateSlots();
        await _configure();
      }
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(
          syncSchedule().catchError((Object e) {
            error = '$e';
            notifyListeners();
          }),
        );
      }
    }
  }

  Future<void> command(String action, [Json args = const {}]) async {
    if (!supported) throw UnsupportedError('首版录音仅支持 Android');
    if (action == 'start') {
      final allowed = await native.invokeMethod<bool>('permission');
      if (allowed != true) throw StateError('需要麦克风权限');
    }
    await native.invokeMethod(action, args);
  }

  /// Ignore replayed events and older revisions after reconnecting.
  void applyTranscriptEvent(Json data) {
    if (data['type'] != 'segment') return;
    final cursor = (data['cursor'] as num?)?.toInt() ?? 0;
    if (cursor <= _cursor) return;
    final segment = Json.from(data['segment'] as Map);
    _cursor = cursor;
    if (segment.containsKey('replace_from')) {
      final from = segment['replace_from'] as num;
      transcript.removeWhere(
        (s) => (s['end'] as num) > from && (from == 0 || s['final'] != true),
      );
    } else {
      final existing = transcript
          .where((s) => s['id'] == segment['id'])
          .firstOrNull;
      if (existing != null &&
          (existing['version'] as num? ?? 0) >
              (segment['version'] as num? ?? 0)) {
        return;
      }
      transcript.removeWhere((s) => s['id'] == segment['id']);
      transcript.add(segment);
      transcript.sort(
        (a, b) => (a['start'] as num).compareTo(b['start'] as num),
      );
    }
    notifyListeners();
  }

  Future<void> retryTranscription() async {
    final task = liveTask;
    if (task != null && ['failed', 'stopped'].contains(task['status'])) {
      await api('POST', '/tasks/${task['id']}/retry');
    }
    liveTask = null;
    await command('retry');
    _connect();
    notifyListeners();
    await _checkLiveHealth();
  }

  Future<void> _checkLiveHealth() async {
    if (_checkingHealth ||
        _streamId.isEmpty ||
        !enabled ||
        baseUrl.isEmpty ||
        apiKey.isEmpty) {
      return;
    }
    _checkingHealth = true;
    final id = _streamId;
    final cursor = _cursor;
    try {
      final tasks = await api('GET', '/tasks') as List? ?? [];
      if (id != _streamId) return;
      liveTask = tasks
          .whereType<Map>()
          .where((t) => t['recording_id'] == id && t['kind'] == 'live')
          .map(Json.from)
          .firstOrNull;
      // Recover persisted text even if a proxy blocks WebSocket upgrades.
      if (!streamConnected) {
        final rows =
            await api('GET', '/recordings/$id/transcript') as List? ?? [];
        if (id != _streamId || cursor != _cursor || streamConnected) return;
        transcript = rows.map((r) => Json.from(r as Map)).toList()
          ..sort((a, b) => (a['start'] as num).compareTo(b['start'] as num));
      }
      notifyListeners();
    } catch (e) {
      if (id == _streamId) {
        streamError = '无法读取转写状态：$e';
        notifyListeners();
      }
    } finally {
      _checkingHealth = false;
    }
  }

  void _connect() {
    final generation = ++_connectionGeneration;
    _reconnect?.cancel();
    _socket?.cancel();
    streamConnected = false;
    if (_streamId.isEmpty || baseUrl.isEmpty || apiKey.isEmpty || !enabled) {
      return;
    }
    final url =
        '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/api/v1/recordings/$_streamId/stream?cursor=$_cursor';
    void retry([String? reason]) {
      if (generation != _connectionGeneration) return;
      streamConnected = false;
      streamError = reason ?? '实时连接已断开，正在重连';
      _reconnect?.cancel();
      _reconnect = Timer(const Duration(seconds: 3), _connect);
      notifyListeners();
    }

    _socket = recordingEvents(url, apiKey).listen(
      (event) {
        if (generation != _connectionGeneration) return;
        try {
          final data = Json.from(jsonDecode(event) as Map);
          streamConnected = true;
          streamError = null;
          if (data['type'] == 'error') streamError = '${data['error']}';
          applyTranscriptEvent(data);
          notifyListeners();
        } catch (e) {
          streamError = '转写消息无法解析：$e';
          notifyListeners();
        }
      },
      onError: (Object e) => retry('实时连接失败，正在重连：$e'),
      onDone: () => retry(),
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localTimer?.cancel();
    _scheduleRetry?.cancel();
    ++_connectionGeneration;
    _streamId = '';
    _healthTimer?.cancel();
    _nativeSub?.cancel();
    _socket?.cancel();
    _reconnect?.cancel();
    super.dispose();
  }
}
