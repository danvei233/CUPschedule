import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/cup_account_service.dart';
import '../account/cup_api_client.dart';
import '../common/stable_fingerprint.dart';
import 'schedule_models.dart';

class ScheduleBundle {
  const ScheduleBundle({required this.semester, required this.schedule});

  final SemesterInfo semester;
  final StudentSchedule schedule;

  ScheduleBundle copyWith({SemesterInfo? semester, StudentSchedule? schedule}) {
    return ScheduleBundle(
      semester: semester ?? this.semester,
      schedule: schedule ?? this.schedule,
    );
  }

  factory ScheduleBundle.fromCupJson({
    required Map<String, dynamic> semesterJson,
    required Map<String, dynamic> printDataJson,
  }) {
    final semester = SemesterInfo.fromJson(semesterJson);
    _assertPrintDataMatchesSemester(semester, printDataJson);
    return ScheduleBundle(
      semester: semester,
      schedule: StudentSchedule.fromCupPrintData(printDataJson),
    );
  }

  Map<String, dynamic> toSemesterJson() => semester.toJson();

  Map<String, dynamic> toPrintDataJson() {
    return schedule.toCupPrintData(semester.sourceSemesterId ?? semester.id);
  }

  static void _assertPrintDataMatchesSemester(
    SemesterInfo semester,
    Map<String, dynamic> printDataJson,
  ) {
    final ids = _printDataSemesterIds(printDataJson).toList()..sort();
    final expectedIds = <int>{
      semester.id,
      if (semester.sourceSemesterId != null) semester.sourceSemesterId!,
    };
    final unexpectedIds = ids.where((id) => !expectedIds.contains(id)).toList();
    if (unexpectedIds.isEmpty) {
      return;
    }

    throw StateError(
      '课表正文属于学期 ${unexpectedIds.join(', ')}，'
      '不是 ${semester.name}(${semester.id})，已拒绝保存',
    );
  }

  static Set<int> _printDataSemesterIds(Map<String, dynamic> printDataJson) {
    final ids = <int>{};

    void addId(Object? raw) {
      final id = switch (raw) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      };
      if (id != null && id > 0) {
        ids.add(id);
      }
    }

    void collect(Object? value) {
      if (value is Iterable) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is! Map<dynamic, dynamic>) {
        return;
      }

      final semester = value['semester'];
      if (semester is Map<dynamic, dynamic>) {
        addId(semester['id']);
      }
      addId(value['semesterId']);

      for (final item in value.values) {
        collect(item);
      }
    }

    collect(printDataJson['studentTableVms']);
    return ids;
  }
}

abstract class ScheduleRepository {
  const ScheduleRepository();

  Future<ScheduleBundle> load();
}

class CupScheduleRepository implements ScheduleRepository {
  const CupScheduleRepository({
    this.store = const ImportedScheduleStore(),
    this.accountService = const CupAccountService(),
  });

  final ImportedScheduleStore store;
  final CupAccountService accountService;

  @override
  Future<ScheduleBundle> load() async {
    final imported = await store.load();
    if (imported != null) {
      unawaited(ScheduleWidgetBridge.refreshTodayClassesAndReminders());
      return imported;
    }

    return _importDefaultCupSchedule(store);
  }

  Future<ScheduleBundle> _importDefaultCupSchedule(
    ImportedScheduleStore store,
  ) async {
    CupApiClient? client;
    try {
      final lease = await accountService.acquireSession();
      client = lease.client;
      final semester = _defaultSemester(lease.session);
      if (semester == null) {
        throw StateError('教务系统没有可导入的学期');
      }
      final payload = await client.fetchSchedule(lease.session, semester);
      return store.save(
        semesterJson: payload.semesterJson,
        printDataJson: payload.printDataJson,
        selectAfterSave: true,
        updateSourceFingerprint: true,
      );
    } on Object catch (error) {
      final message = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '');
      throw StateError('首次课表导入失败：$message');
    } finally {
      client?.close();
    }
  }

  CupSemesterOption? _defaultSemester(CupCourseTableSession session) {
    final currentSemesterId = session.currentSemesterId;
    if (currentSemesterId != null) {
      for (final semester in session.semesters) {
        if (semester.id == currentSemesterId) {
          return semester;
        }
      }
    }

    final today = DateTime.now();
    for (final semester in session.semesters) {
      if (!today.isBefore(semester.startDate) &&
          !today.isAfter(semester.endDate)) {
        return semester;
      }
    }
    return session.semesters.isEmpty ? null : session.semesters.first;
  }
}

class ImportedScheduleStore {
  const ImportedScheduleStore();

  static const _semesterIdsKey = 'cup.imported.semester.ids';
  static const _selectedSemesterIdKey = 'cup.imported.selected_semester_id';
  static const _semesterPrefix = 'cup.imported.semester.';
  static const _printDataPrefix = 'cup.imported.print_data.';
  static const _fingerprintPrefix = 'cup.imported.fingerprint.';
  static const _sourceFingerprintPrefix = 'cup.imported.source_fingerprint.';
  static const _startDateOverridePrefix = 'cup.imported.start_date_override.';
  static const _conflictChoicePrefix = 'cup.imported.conflict_choice.';
  static const _semesterKey = 'cup.imported.semester.json';
  static const _printDataKey = 'cup.imported.print_data.json';

  Future<ScheduleBundle?> load() => loadSelected();

  Future<ScheduleBundle?> loadSelected() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final selectedId = preferences.getInt(_selectedSemesterIdKey);
    if (selectedId != null) {
      final selected = _applyLocalSettings(
        preferences,
        _loadBundle(preferences, selectedId),
      );
      if (selected != null) {
        return selected;
      }
    }

    final bundles = await loadAll();
    if (bundles.isNotEmpty) {
      return bundles.first;
    }

    return _loadLegacy(preferences);
  }

  Future<List<ScheduleBundle>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final ids = preferences.getStringList(_semesterIdsKey) ?? const [];
    final bundles = <ScheduleBundle>[];
    for (final rawId in ids) {
      final id = int.tryParse(rawId);
      if (id == null) {
        continue;
      }
      final bundle = _applyLocalSettings(
        preferences,
        _loadBundle(preferences, id),
      );
      if (bundle != null) {
        bundles.add(bundle);
      }
    }

    if (bundles.isEmpty) {
      final legacy = _loadLegacy(preferences);
      if (legacy != null) {
        bundles.add(legacy);
      }
    }

    bundles.sort((a, b) {
      return b.semester.startDate.compareTo(a.semester.startDate);
    });
    return bundles;
  }

  Future<bool> containsSemester(int semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    return _loadBundle(preferences, semesterId) != null;
  }

  Future<String?> fingerprintForSemester(int semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    return preferences.getString('$_fingerprintPrefix$semesterId');
  }

  Future<String?> sourceFingerprintForSemester(int semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    return preferences.getString('$_sourceFingerprintPrefix$semesterId');
  }

  Future<void> setSelectedSemesterId(int semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_selectedSemesterIdKey, semesterId);
    await ScheduleWidgetBridge.refreshTodayClassesAndReminders();
  }

  Future<int?> selectedSemesterId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_selectedSemesterIdKey);
  }

  Future<int> nextLocalSemesterId() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final ids = preferences.getStringList(_semesterIdsKey) ?? const [];
    var candidate = -DateTime.now().microsecondsSinceEpoch;
    while (ids.contains(candidate.toString()) ||
        _loadBundle(preferences, candidate) != null) {
      candidate--;
    }
    return candidate;
  }

  Future<void> setSemesterStartDate(int semesterId, DateTime startDate) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_startDateOverridePrefix$semesterId',
      _dateText(startDate),
    );
    await ScheduleWidgetBridge.refreshTodayClassesAndReminders();
  }

  static String conflictChoiceKey({
    required int weekIndex,
    required String groupKey,
  }) {
    return '$weekIndex.$groupKey';
  }

  Future<Map<String, String>> loadConflictChoices(int semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = '$_conflictChoicePrefix$semesterId.';
    final choices = <String, String>{};
    for (final key in preferences.getKeys()) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      final value = preferences.getString(key);
      if (value == null || value.isEmpty) {
        continue;
      }
      choices[key.substring(prefix.length)] = value;
    }
    return choices;
  }

  Future<void> setConflictChoice({
    required int semesterId,
    required int weekIndex,
    required String groupKey,
    required String selectedActivityKey,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_conflictChoicePrefix$semesterId.'
      '${conflictChoiceKey(weekIndex: weekIndex, groupKey: groupKey)}',
      selectedActivityKey,
    );
    await ScheduleWidgetBridge.refreshTodayClassesAndReminders();
  }

  ScheduleBundle? _loadBundle(SharedPreferences preferences, int semesterId) {
    final semesterText = preferences.getString('$_semesterPrefix$semesterId');
    final printDataText = preferences.getString('$_printDataPrefix$semesterId');
    if (semesterText == null || printDataText == null) {
      return null;
    }

    try {
      return ScheduleBundle.fromCupJson(
        semesterJson: jsonDecode(semesterText) as Map<String, dynamic>,
        printDataJson: jsonDecode(printDataText) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  ScheduleBundle? _applyLocalSettings(
    SharedPreferences preferences,
    ScheduleBundle? bundle,
  ) {
    if (bundle == null) {
      return null;
    }
    final override = preferences.getString(
      '$_startDateOverridePrefix${bundle.semester.id}',
    );
    final startDate = override == null ? null : DateTime.tryParse(override);
    if (startDate == null) {
      return bundle;
    }
    return ScheduleBundle(
      semester: bundle.semester.copyWith(startDate: startDate),
      schedule: bundle.schedule,
    );
  }

  ScheduleBundle? _loadLegacy(SharedPreferences preferences) {
    final semesterText = preferences.getString(_semesterKey);
    final printDataText = preferences.getString(_printDataKey);
    if (semesterText == null || printDataText == null) {
      return null;
    }

    try {
      return ScheduleBundle.fromCupJson(
        semesterJson: jsonDecode(semesterText) as Map<String, dynamic>,
        printDataJson: jsonDecode(printDataText) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _migrateLegacyIfNeeded(SharedPreferences preferences) async {
    final semesterText = preferences.getString(_semesterKey);
    final printDataText = preferences.getString(_printDataKey);
    if (semesterText == null || printDataText == null) {
      return;
    }

    final Map<String, dynamic> semesterJson;
    final Map<String, dynamic> printDataJson;
    final ScheduleBundle bundle;
    try {
      semesterJson = jsonDecode(semesterText) as Map<String, dynamic>;
      printDataJson = jsonDecode(printDataText) as Map<String, dynamic>;
      bundle = ScheduleBundle.fromCupJson(
        semesterJson: semesterJson,
        printDataJson: printDataJson,
      );
    } on Object {
      return;
    }

    final semesterId = bundle.semester.id;
    final idText = semesterId.toString();
    final ids = List<String>.of(
      preferences.getStringList(_semesterIdsKey) ?? const [],
    );
    if (!ids.contains(idText)) {
      ids.add(idText);
      await preferences.setStringList(_semesterIdsKey, ids);
    }
    await preferences.setString(
      '$_semesterPrefix$semesterId',
      preferences.getString('$_semesterPrefix$semesterId') ?? semesterText,
    );
    await preferences.setString(
      '$_printDataPrefix$semesterId',
      preferences.getString('$_printDataPrefix$semesterId') ?? printDataText,
    );
    await preferences.setString(
      '$_fingerprintPrefix$semesterId',
      preferences.getString('$_fingerprintPrefix$semesterId') ??
          schedulePayloadFingerprint(
            semesterJson: semesterJson,
            printDataJson: printDataJson,
          ),
    );
    await preferences.setString(
      '$_sourceFingerprintPrefix$semesterId',
      preferences.getString('$_sourceFingerprintPrefix$semesterId') ??
          schedulePayloadFingerprint(
            semesterJson: semesterJson,
            printDataJson: printDataJson,
          ),
    );
    if (preferences.getInt(_selectedSemesterIdKey) == null) {
      await preferences.setInt(_selectedSemesterIdKey, semesterId);
    }
  }

  Future<ScheduleBundle> save({
    required Map<String, dynamic> semesterJson,
    required Map<String, dynamic> printDataJson,
    bool selectAfterSave = true,
    bool updateSourceFingerprint = true,
  }) async {
    final bundle = ScheduleBundle.fromCupJson(
      semesterJson: semesterJson,
      printDataJson: printDataJson,
    );
    final semesterId = bundle.semester.id;
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final ids = preferences.getStringList(_semesterIdsKey) ?? <String>[];
    final idText = semesterId.toString();
    if (!ids.contains(idText)) {
      ids.add(idText);
    }
    await preferences.setStringList(_semesterIdsKey, ids);
    if (selectAfterSave) {
      await preferences.setInt(_selectedSemesterIdKey, semesterId);
    }
    await preferences.setString(
      '$_semesterPrefix$semesterId',
      jsonEncode(semesterJson),
    );
    await preferences.setString(
      '$_printDataPrefix$semesterId',
      jsonEncode(printDataJson),
    );
    final fingerprint = schedulePayloadFingerprint(
      semesterJson: semesterJson,
      printDataJson: printDataJson,
    );
    await preferences.setString('$_fingerprintPrefix$semesterId', fingerprint);
    if (updateSourceFingerprint) {
      await preferences.setString(
        '$_sourceFingerprintPrefix$semesterId',
        fingerprint,
      );
    }
    await ScheduleWidgetBridge.refreshTodayClassesAndReminders();
    return bundle;
  }

  Future<ScheduleBundle> saveBundle(
    ScheduleBundle bundle, {
    bool selectAfterSave = true,
    bool updateSourceFingerprint = false,
  }) {
    return save(
      semesterJson: bundle.toSemesterJson(),
      printDataJson: bundle.toPrintDataJson(),
      selectAfterSave: selectAfterSave,
      updateSourceFingerprint: updateSourceFingerprint,
    );
  }

  Future<ScheduleBundle> renameSemester(int semesterId, String name) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final bundle = _loadBundle(preferences, semesterId);
    if (bundle == null) {
      throw StateError('课表不存在');
    }
    return saveBundle(
      bundle.copyWith(semester: bundle.semester.copyWith(name: name)),
      selectAfterSave: preferences.getInt(_selectedSemesterIdKey) == semesterId,
    );
  }

  Future<void> deleteSemester(int semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final idText = semesterId.toString();
    final ids = List<String>.of(
      preferences.getStringList(_semesterIdsKey) ?? const [],
    )..remove(idText);
    await preferences.setStringList(_semesterIdsKey, ids);
    await preferences.remove('$_semesterPrefix$semesterId');
    await preferences.remove('$_printDataPrefix$semesterId');
    await preferences.remove('$_fingerprintPrefix$semesterId');
    await preferences.remove('$_sourceFingerprintPrefix$semesterId');
    await preferences.remove('$_startDateOverridePrefix$semesterId');
    for (final key in preferences.getKeys()) {
      if (key.startsWith('$_conflictChoicePrefix$semesterId.')) {
        await preferences.remove(key);
      }
    }
    if (preferences.getInt(_selectedSemesterIdKey) == semesterId) {
      if (ids.isEmpty) {
        await preferences.remove(_selectedSemesterIdKey);
      } else {
        await preferences.setInt(_selectedSemesterIdKey, int.parse(ids.first));
      }
    }
    await ScheduleWidgetBridge.refreshTodayClassesAndReminders();
  }

  Future<ScheduleBundle> upsertCourse({
    required int semesterId,
    required CourseActivity activity,
    String? replaceActivityKey,
  }) async {
    return upsertCourses(
      semesterId: semesterId,
      activities: [activity],
      replaceActivityKeys: replaceActivityKey == null
          ? null
          : [replaceActivityKey],
    );
  }

  Future<ScheduleBundle> upsertCourses({
    required int semesterId,
    required List<CourseActivity> activities,
    List<String>? replaceActivityKeys,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final bundle = _loadBundle(preferences, semesterId);
    if (bundle == null) {
      throw StateError('课表不存在');
    }
    final replacementKeys = {
      ...?replaceActivityKeys,
      for (final activity in activities) _activityStorageKey(activity),
    };
    final nextActivities = [
      for (final activity in bundle.schedule.activities)
        if (!replacementKeys.contains(_activityStorageKey(activity))) activity,
      ...activities,
    ]..sort(CourseActivity.compareByTime);
    return saveBundle(
      bundle.copyWith(
        schedule: bundle.schedule.copyWith(activities: nextActivities),
      ),
      selectAfterSave: preferences.getInt(_selectedSemesterIdKey) == semesterId,
    );
  }

  Future<ScheduleBundle> deleteCourse({
    required int semesterId,
    String? activityKey,
    List<String>? activityKeys,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(preferences);
    final bundle = _loadBundle(preferences, semesterId);
    if (bundle == null) {
      throw StateError('课表不存在');
    }
    final keys = {?activityKey, ...?activityKeys};
    final activities = bundle.schedule.activities
        .where((activity) => !keys.contains(_activityStorageKey(activity)))
        .toList();
    return saveBundle(
      bundle.copyWith(
        schedule: bundle.schedule.copyWith(activities: activities),
      ),
      selectAfterSave: preferences.getInt(_selectedSemesterIdKey) == semesterId,
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_semesterIdsKey) ?? const [];
    for (final id in ids) {
      await preferences.remove('$_semesterPrefix$id');
      await preferences.remove('$_printDataPrefix$id');
      await preferences.remove('$_fingerprintPrefix$id');
      await preferences.remove('$_sourceFingerprintPrefix$id');
      await preferences.remove('$_startDateOverridePrefix$id');
    }
    for (final key in preferences.getKeys()) {
      if (key.startsWith(_conflictChoicePrefix)) {
        await preferences.remove(key);
      }
    }
    await preferences.remove(_semesterIdsKey);
    await preferences.remove(_selectedSemesterIdKey);
    await preferences.remove(_semesterKey);
    await preferences.remove(_printDataKey);
    await ScheduleWidgetBridge.refreshTodayClassesAndReminders();
  }

  String _dateText(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

enum TodayWidgetContentMode {
  live('live', '实时今日'),
  fixed('fixed', '指定时间');

  const TodayWidgetContentMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static TodayWidgetContentMode fromStorage(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return TodayWidgetContentMode.live;
  }
}

class TodayWidgetDisplaySettings {
  const TodayWidgetDisplaySettings({
    required this.mode,
    required this.fixedDate,
    required this.fixedTime,
  });

  factory TodayWidgetDisplaySettings.live() {
    final now = DateTime.now();
    return TodayWidgetDisplaySettings(
      mode: TodayWidgetContentMode.live,
      fixedDate: DateTime(now.year, now.month, now.day),
      fixedTime: TimeOfDay(hour: now.hour, minute: now.minute),
    );
  }

  final TodayWidgetContentMode mode;
  final DateTime fixedDate;
  final TimeOfDay fixedTime;

  String get fixedDateText {
    return '${fixedDate.year.toString().padLeft(4, '0')}-'
        '${fixedDate.month.toString().padLeft(2, '0')}-'
        '${fixedDate.day.toString().padLeft(2, '0')}';
  }

  String get fixedTimeText {
    return '${fixedTime.hour.toString().padLeft(2, '0')}:'
        '${fixedTime.minute.toString().padLeft(2, '0')}';
  }

  TodayWidgetDisplaySettings copyWith({
    TodayWidgetContentMode? mode,
    DateTime? fixedDate,
    TimeOfDay? fixedTime,
  }) {
    return TodayWidgetDisplaySettings(
      mode: mode ?? this.mode,
      fixedDate: fixedDate ?? this.fixedDate,
      fixedTime: fixedTime ?? this.fixedTime,
    );
  }
}

class TodayWidgetDisplaySettingsStore {
  const TodayWidgetDisplaySettingsStore();

  static const _modeKey = 'widget.today.content_mode';
  static const _fixedDateKey = 'widget.today.fixed_date';
  static const _fixedTimeKey = 'widget.today.fixed_time';

  Future<TodayWidgetDisplaySettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final fallback = TodayWidgetDisplaySettings.live();
    return TodayWidgetDisplaySettings(
      mode: TodayWidgetContentMode.fromStorage(preferences.getString(_modeKey)),
      fixedDate:
          DateTime.tryParse(preferences.getString(_fixedDateKey) ?? '') ??
          fallback.fixedDate,
      fixedTime:
          _parseTime(preferences.getString(_fixedTimeKey)) ??
          fallback.fixedTime,
    );
  }

  Future<void> save(TodayWidgetDisplaySettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_modeKey, settings.mode.storageValue);
    await preferences.setString(_fixedDateKey, settings.fixedDateText);
    await preferences.setString(_fixedTimeKey, settings.fixedTimeText);
    await ScheduleWidgetBridge.setWidgetDisplaySettings(settings);
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null) {
      return null;
    }
    final parts = raw.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }
}

class ScheduleWidgetBridge {
  static const MethodChannel _channel = MethodChannel(
    'blackbook/today_classes_widget',
  );

  static Future<void> setThemePreference(String preference) async {
    final payload = await _buildTodayWidgetPayload();
    final arguments = <String, Object?>{'preference': preference};
    if (payload != null) {
      arguments['payload'] = payload;
    }
    await _invokeWidgetMethod('setThemePreference', arguments);
  }

  static Future<void> setWidgetDisplaySettings(
    TodayWidgetDisplaySettings settings,
  ) async {
    final payload = await _buildTodayWidgetPayload(settings: settings);
    final arguments = <String, Object?>{
      'mode': settings.mode.storageValue,
      'date': settings.fixedDateText,
      'time': settings.fixedTimeText,
    };
    if (payload != null) {
      arguments['payload'] = payload;
    }
    await _invokeWidgetMethod('setWidgetDisplaySettings', arguments);
  }

  static Future<void> refreshTodayClasses() async {
    final payload = await _buildTodayWidgetPayload();
    await _invokeWidgetMethod<void>(
      'refresh',
      payload == null ? null : <String, Object?>{'payload': payload},
    );
  }

  static Future<void> refreshTodayClassesAndReminders() async {
    await refreshTodayClasses();
    await scheduleClassReminders();
  }

  static Future<void> scheduleClassReminders() async {
    await _invokeWidgetMethod<void>('scheduleClassReminders');
  }

  static Future<bool> showClassReminderTest() async {
    return await _invokeWidgetMethod<bool>('showClassReminderTest') ?? false;
  }

  static Future<T?> _invokeWidgetMethod<T>(
    String method, [
    Object? arguments,
  ]) async {
    try {
      WidgetsBinding.instance;
    } on FlutterError {
      return null;
    }
    final messenger = ServicesBinding.instance.defaultBinaryMessenger;
    if (messenger.runtimeType.toString().contains('Test')) {
      return null;
    }
    try {
      return await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(seconds: 1));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static Future<Map<String, Object?>?> _buildTodayWidgetPayload({
    TodayWidgetDisplaySettings? settings,
  }) async {
    try {
      final displaySettings =
          settings ?? await const TodayWidgetDisplaySettingsStore().load();
      final now = DateTime.now();
      final referenceDate = displaySettings.mode == TodayWidgetContentMode.fixed
          ? displaySettings.fixedDate
          : now;
      final referenceTime = displaySettings.mode == TodayWidgetContentMode.fixed
          ? displaySettings.fixedTime
          : TimeOfDay(hour: now.hour, minute: now.minute);
      final bundle = await ImportedScheduleStore().loadSelected();
      if (bundle == null) {
        return <String, Object?>{
          'title': '今日课程',
          'subtitle': '还没有导入课表',
          'referenceTime': _clockText(referenceTime),
          'courses': const <Object?>[],
        };
      }

      final semester = bundle.semester;
      final weekIndex = semester.weekIndexFor(referenceDate);
      final weekday = referenceDate.weekday;
      final referenceMinutes = referenceTime.hour * 60 + referenceTime.minute;
      final dateInSemester =
          !referenceDate.isBefore(semester.startDate) &&
          !referenceDate.isAfter(semester.endDate);
      final courses = dateInSemester
          ? (bundle.schedule.activities
                .where(
                  (activity) =>
                      activity.weekday == weekday &&
                      activity.weekIndexes.contains(weekIndex) &&
                      _clockMinutes(activity.endTime) > referenceMinutes,
                )
                .toList()
              ..sort(CourseActivity.compareByTime))
          : <CourseActivity>[];
      return <String, Object?>{
        'title': '今日课程',
        'subtitle':
            '${semester.name}  第$weekIndex周  ${_dateText(referenceDate)}',
        'referenceTime': _clockText(referenceTime),
        'courses': courses
            .map(
              (activity) => <String, Object?>{
                'name': activity.courseName,
                'time': '${activity.startTime}-${activity.endTime}',
                'place': activity.placeText,
                'teacher': activity.teacherText,
                'iconKey': activity.iconKey,
                'colorKey': activity.colorKey,
              },
            )
            .toList(),
      };
    } on Object {
      return null;
    }
  }

  static int _clockMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return 0;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }

  static String _clockText(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static String _dateText(DateTime value) {
    return '${value.month}/${value.day}';
  }
}

String scheduleActivityStorageKey(CourseActivity activity) {
  return _activityStorageKey(activity);
}

String scheduleCourseGroupKey(CourseActivity activity) {
  return [
    activity.lessonId,
    activity.courseCode,
    activity.courseName,
  ].join('|');
}

String schedulePayloadFingerprint({
  required Map<String, dynamic> semesterJson,
  required Map<String, dynamic> printDataJson,
}) {
  return stableJsonFingerprint({
    'sourceSemesterId': semesterJson['sourceSemesterId'] ?? semesterJson['id'],
    'startDate': semesterJson['startDate'],
    'endDate': semesterJson['endDate'],
    'printData': printDataJson,
  });
}

String _activityStorageKey(CourseActivity activity) {
  return [
    activity.lessonId,
    activity.lessonCode,
    activity.courseCode,
    activity.weekday,
    activity.startUnit,
    activity.endUnit,
    activity.courseName,
  ].join('|');
}
