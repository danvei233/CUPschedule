import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import 'recording_controller.dart';
import 'course_cards.dart';
import 'recording_sync.dart';
import 'audio_model_panel.dart';
import 'recording_settings_layout.dart';
import 'live_recorder.dart';

Future<String?> editRecordingText(
  BuildContext context,
  String title,
  String value, {
  bool multiline = false,
  bool secret = false,
}) async {
  final controller = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 540,
        child: TextField(
          controller: controller,
          autofocus: true,
          obscureText: secret,
          minLines: multiline ? 5 : 1,
          maxLines: multiline ? 16 : 1,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Dialog route animations can still reference the controller after pop.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

Future<bool> confirmRecordingDelete(
  BuildContext context,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;

String durationLabel(num seconds) {
  final value = seconds.toInt();
  return '${value ~/ 3600}:${((value % 3600) ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
}

class RecordingCenter extends StatefulWidget {
  const RecordingCenter({super.key});
  @override
  State<RecordingCenter> createState() => _RecordingCenterState();
}

class _RecordingCenterState extends State<RecordingCenter> {
  final controller = RecordingController.instance;
  int tab = 0;
  bool busy = false;
  String selectedCourse = 'misc';
  String? message;
  @override
  void initState() {
    super.initState();
    controller.addListener(refresh);
    unawaited(
      run(() async {
        await controller.load();
        await controller.syncSchedule();
      }),
    );
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(refresh);
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          message = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('课堂记录'),
      actions: [
        IconButton(
          tooltip: '同步课表',
          onPressed: busy ? null : () => run(controller.syncSchedule),
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (message != null || controller.error != null)
          MaterialBanner(
            content: Text(message ?? controller.error!),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    message = null;
                    controller.error = null;
                  });
                },
                child: const Text('知道了'),
              ),
            ],
          ),
        Expanded(
          child: IndexedStack(
            index: tab,
            children: [
              courseList(),
              recorder(),
              RecordingSettings(
                onError: (text) => setState(() {
                  message = text;
                }),
              ),
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) {
        setState(() {
          tab = value;
          if (value == 1 && !controller.recording) {
            final now = DateTime.now();
            selectedCourse =
                controller.slots
                    .where(
                      (s) =>
                          !now.isBefore(
                            s.start.subtract(const Duration(minutes: 1)),
                          ) &&
                          now.isBefore(s.end),
                    )
                    .firstOrNull
                    ?.courseId ??
                'misc';
          }
        });
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.school_outlined), label: '课程列表'),
        NavigationDestination(icon: Icon(Icons.mic_none), label: '当前录制'),
        NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
      ],
    ),
  );
  Widget courseList() {
    final now = DateTime.now();
    final current = controller.semesters
        .where(
          (s) =>
              !now.isBefore(s.semester.startDate) &&
              now.isBefore(s.semester.endDate.add(const Duration(days: 1))),
        )
        .map((s) => '${s.semester.id}')
        .toSet();
    final rows = controller.courses
        .where(
          (r) =>
              (r['course'] as Map)['id'] == 'misc' ||
              current.contains((r['course'] as Map)['semester_id']),
        )
        .toList();
    for (final local in controller.localRecordings) {
      if (!rows.any((r) => (r['course'] as Map)['id'] == local['course_id'])) {
        final known = controller.courses
            .where((r) => (r['course'] as Map)['id'] == local['course_id'])
            .firstOrNull;
        rows.add(
          known ??
              {
                'course': {
                  'id': local['course_id'],
                  'name': local['course_id'] == 'misc' ? '随手录音' : '本机课程录音',
                  'auto_record': false,
                },
                'recording_count': 0,
                'duration_seconds': 0,
              },
        );
      }
    }
    return RefreshIndicator(
      onRefresh: controller.syncSchedule,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('把每节课留下来', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('本学期 · 录音、原文与课堂笔记'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('本机录音与同步'),
              subtitle: Text(
                '${controller.localRecordings.where((r) => r['uploaded'] != true).length} 条待上传 · 断网保存，联网补传',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const RecordingSyncPage(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('先在设置中连接后端，再同步已有课表。'),
            ),
          CourseGrid(
            rows: rows,
            onOpen: (course) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => RecordingCoursePage(course: course),
                ),
              );
              if (mounted) await run(controller.syncSchedule);
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => run(() async {
              final name = await editRecordingText(context, '新建课程', '');
              if (name == null || name.trim().isEmpty) return;
              await controller.api('POST', '/courses', {
                'name': name,
                'semester_id': current.firstOrNull ?? '',
              });
              await controller.refreshCourses();
            }),
            icon: const Icon(Icons.add),
            label: const Text('新建课程'),
          ),
        ],
      ),
    );
  }

  Widget recorder() {
    if (!controller.recording) {
      final all = controller.courses
          .map((r) => Json.from(r['course'] as Map))
          .toList();
      if (!all.any((c) => c['id'] == 'misc')) {
        all.add({'id': 'misc', 'name': 'misc'});
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 28),
          const Icon(Icons.mic_none, size: 72),
          const SizedBox(height: 24),
          Text(
            '开始一份课堂记录',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: all.any((c) => c['id'] == selectedCourse)
                ? selectedCourse
                : 'misc',
            decoration: const InputDecoration(
              labelText: '所属课程',
              border: OutlineInputBorder(),
            ),
            items: all
                .map(
                  (c) => DropdownMenuItem(
                    value: '${c['id']}',
                    child: Text('${c['name']}'),
                  ),
                )
                .toList(),
            onChanged: (v) => selectedCourse = v ?? 'misc',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => run(
                    () => controller.command('start', {
                      'course_id': selectedCourse,
                    }),
                  ),
            icon: const Icon(Icons.mic),
            label: const Text('开始录音'),
          ),
          const SizedBox(height: 12),
          const Text('断网仍会保存在设备上，连接恢复后自动上传。'),
        ],
      );
    }
    return LiveRecorder(
      controller: controller,
      busy: busy,
      onCommand: (action) => run(() => controller.command(action)),
      onRetry: () => run(controller.retryTranscription),
    );
  }
}

class RecordingSettings extends StatefulWidget {
  const RecordingSettings({super.key, required this.onError});
  final ValueChanged<String> onError;
  @override
  State<RecordingSettings> createState() => _RecordingSettingsState();
}

class _RecordingSettingsState extends State<RecordingSettings> {
  final c = RecordingController.instance;
  Json server = {};
  int section = 0;
  bool loading = false;
  List<Json> tasks = [];
  static const taskLabels = {
    'live': '实时转写',
    'transcribe': '录音转写',
    'note': '生成笔记',
    'cleanup': '文件清理',
    'queued': '排队中',
    'running': '处理中',
    'stopping': '正在停止',
    'stopped': '已停止',
    'succeeded': '已完成',
    'failed': '失败',
    'waiting_config': '等待配置',
  };

  bool? rooted;
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    unawaited(load(silent: true));
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (c.enabled && c.baseUrl.isNotEmpty && !busy) {
        unawaited(load(silent: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() f) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await f();
    } catch (e) {
      widget.onError('$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> load({bool silent = false}) async {
    if (loading) return;
    loading = true;
    try {
      final settings = Json.from(await c.api('GET', '/settings') as Map);
      final rows = (await c.api('GET', '/tasks')) as List? ?? [];
      if (mounted) {
        setState(() {
          server = Json.from(settings['settings'] as Map);
          tasks = rows.map((e) => Json.from(e as Map)).toList();
        });
      }
    } catch (e) {
      if (!silent) rethrow;
    } finally {
      loading = false;
    }
  }

  Future<void> serverField(
    String field,
    String label, {
    bool multiline = false,
    bool secret = false,
    bool number = false,
  }) async {
    final text = await editRecordingText(
      context,
      label,
      secret ? '' : '${server[field] ?? ''}',
      multiline: multiline,
      secret: secret,
    );
    if (text == null) return;
    await c.api('PATCH', '/settings', {field: number ? int.parse(text) : text});
    await load();
  }

  Widget field(
    String key,
    String label, {
    bool multiline = false,
    bool secret = false,
    bool number = false,
  }) => ListTile(
    title: Text(label),
    subtitle: Text(
      secret ? '点击更新；保存空值会清空服务端密钥' : '${server[key] ?? '点击设置'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.edit_outlined),
    onTap: () => perform(
      () => serverField(
        key,
        label,
        multiline: multiline,
        secret: secret,
        number: number,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => RecordingSettingsLayout(
    selected: section,
    onSelected: (value) => setState(() => section = value),
    busy: busy,
    onRefresh: () => perform(load),
    summaries: [
      c.baseUrl.isEmpty ? '尚未配置后端' : c.baseUrl,
      c.autoRecord ? '自动录音已开启' : '自动录音已关闭',
      '${server['audio_url'] ?? '模型服务与推理并发'}',
      '${server['model'] ?? '模型与生成参数'}',
      '转写术语、全局与课程要求',
      '${tasks.where((t) => ['running', 'queued', 'stopping'].contains(t['status'])).length} 个待处理或运行中的任务',
    ],
    children: sectionContent(),
  );

  List<Widget> sectionContent() => switch (section) {
    0 => [
      ListTile(
        title: const Text('后端地址'),
        subtitle: Text(
          c.baseUrl.isEmpty ? '例如 http://192.168.1.2:8090' : c.baseUrl,
        ),
        onTap: () => perform(() async {
          final text = await editRecordingText(
            context,
            '后端地址（不含 /api/v1）',
            c.baseUrl,
          );
          if (text != null) {
            c.baseUrl = text.trim();
            await c.saveLocal();
          }
        }),
      ),
      ListTile(
        title: const Text('后端 API key'),
        subtitle: Text(c.apiKey.isEmpty ? '未设置' : '已设置'),
        onTap: () => perform(() async {
          final text = await editRecordingText(
            context,
            '后端 API key',
            '',
            secret: true,
          );
          if (text != null) {
            c.apiKey = text;
            await c.saveLocal();
          }
        }),
      ),
      FilledButton.tonal(
        onPressed: () => perform(() async {
          await load();
          await c.syncSchedule();
          await c.command('retry');
        }),
        child: const Text('连接、同步并重试上传'),
      ),
      ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: const Text('本机录音与同步'),
        subtitle: const Text('查看离线录音、上传进度和失败原因'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const RecordingSyncPage()),
        ),
      ),
    ],
    1 => [
      SwitchListTile(
        title: const Text('按课表自动录音'),
        subtitle: Text(
          (c.status['selftest'] as Map?)?['passed'] == true
              ? '提前 1 分钟；同课连续节次自动合并'
              : '开启前，请在下方「后台录音与设备诊断」完成锁屏自检',
        ),
        value: c.autoRecord,
        onChanged:
            c.autoRecord || (c.status['selftest'] as Map?)?['passed'] == true
            ? (v) => perform(() async {
                c.autoRecord = v;
                await c.saveLocal();
                await c.syncSchedule();
              })
            : null,
      ),
      DropdownButtonFormField<String>(
        initialValue:
            c.semesters.any((s) => '${s.semester.id}' == c.activeSemester)
            ? c.activeSemester
            : '',
        decoration: const InputDecoration(labelText: '自动录音学期'),
        items: [
          const DropdownMenuItem(value: '', child: Text('按当前日期自动选择')),
          ...c.semesters.map(
            (s) => DropdownMenuItem(
              value: '${s.semester.id}',
              child: Text(s.semester.name),
            ),
          ),
        ],
        onChanged: (v) => perform(() async {
          c.activeSemester = v ?? '';
          await c.saveLocal();
          await c.syncSchedule();
        }),
      ),
      ListTile(
        title: const Text('课间合并上限'),
        subtitle: Text('${c.mergeGap} 分钟'),
        onTap: () => perform(() async {
          final v = await editRecordingText(
            context,
            '相邻节次最大间隔（分钟）',
            '${c.mergeGap}',
          );
          if (v != null) {
            c.mergeGap = int.parse(v).clamp(0, 120);
            await c.saveLocal();
            await c.syncSchedule();
          }
        }),
      ),
      const ListTile(
        title: Text('本地音频保留'),
        subtitle: Text('完整上传并校验后保留 7 天；未上传数据不会自动删除'),
      ),
      ExpansionTile(
        title: const Text('后台录音与设备诊断'),
        subtitle: Text(
          c.status['daemon'] == true
              ? '守护运行中 · root 与麦克风自检'
              : '设置守护、检测 root 与后台麦克风',
        ),
        leading: const Icon(Icons.security_outlined),
        children: [
          ListTile(
            title: Text(
              'root：${rooted == null
                  ? '未检测'
                  : rooted!
                  ? '已授权'
                  : '未授权'}',
            ),
            trailing: OutlinedButton(
              onPressed: () => perform(() async {
                final value = await RecordingController.native
                    .invokeMethod<bool>('root');
                if (mounted) {
                  setState(() {
                    rooted = value;
                  });
                }
              }),
              child: const Text('检测'),
            ),
          ),
          ListTile(
            title: Text('守护：${c.status['daemon'] == true ? '运行中' : '未运行'}'),
            subtitle: Text(
              '${c.status['install_stage'] ?? ''}'.isNotEmpty
                  ? '${c.status['install_stage']}…'
                  : '更新会结束当前录音并保留待上传数据，无需重启设备。更新后请重新自检。',
            ),
            trailing: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      await c.command('install');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('新守护已启动，心跳验证通过；请重新进行锁屏自检'),
                          ),
                        );
                      }
                    }),
              child: const Text('安装 / 更新并重启'),
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => perform(() async {
                        await c.command('stopDaemon');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('守护已停止并禁用开机启动；点击安装 / 更新可重新启用'),
                            ),
                          );
                        }
                      }),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止守护'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => perform(() async {
                        final logs =
                            await RecordingController.native
                                .invokeMethod<String>('daemonLogs') ??
                            '暂无日志';
                        if (!mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('守护日志（最近 120 行）'),
                            content: SizedBox(
                              width: 640,
                              child: SingleChildScrollView(
                                child: SelectableText(logs),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      }),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('查看日志'),
              ),
            ],
          ),
          ListTile(
            title: Text(
              '后台麦克风：${(c.status['selftest'] as Map?)?['passed'] == true ? '自检通过' : '未通过自检'}',
            ),
            subtitle: Text(
              '${(c.status['selftest'] as Map?)?['error'] ?? '点击后请锁屏，15 秒后采集 3 秒音频'}',
            ),
            trailing: OutlinedButton(
              onPressed: () => perform(() => c.command('selftest')),
              child: const Text('自检'),
            ),
          ),
          for (final name in [
            'command-error.txt',
            'service-error.txt',
            'daemon-error.txt',
          ])
            if (c.status[name] != null) Text('${c.status[name]}'),
        ],
      ),
    ],
    2 => [
      field('audio_url', '音频服务地址'),
      field('audio_key', '音频服务内部密钥', secret: true),
      field('gpu_limit', 'GPU 推理并发数', number: true),
      AudioModelPanel(
        control: (action) async => Json.from(
          await c.api(
                action == 'status' ? 'GET' : 'POST',
                '/audio-service${action == 'status' ? '' : '/$action'}',
                action == 'status' ? null : {},
              )
              as Map,
        ),
      ),
    ],
    3 => [
      field('openai_url', 'OpenAI Base URL'),
      field('openai_key', 'OpenAI API key', secret: true),
      field('model', '模型名称'),
      DropdownButtonFormField<String>(
        initialValue: server['protocol'] == 'responses' ? 'responses' : 'chat',
        decoration: const InputDecoration(labelText: '接口协议'),
        items: const [
          DropdownMenuItem(value: 'chat', child: Text('Chat Completions')),
          DropdownMenuItem(value: 'responses', child: Text('Responses')),
        ],
        onChanged: (v) => perform(() async {
          await c.api('PATCH', '/settings', {'protocol': v});
          await load();
        }),
      ),
      field('reasoning', '思考强度（留空不发送）'),
      field('input_budget', '分段输入预算（字符）', number: true),
      field('note_limit', '笔记生成并发数', number: true),
      TextButton(
        onPressed: () => perform(() async {
          final out = await c.api('POST', '/settings/test', {});
          widget.onError('${out['result']}');
        }),
        child: const Text('测试 OpenAI 连接'),
      ),
    ],
    4 => [
      field('transcription_prompt', '转写提示词 / 专业术语', multiline: true),
      field('note_prompt', '全局笔记提示词', multiline: true),
      ListTile(
        title: const Text('课程自定义提示词与录音开关'),
        subtitle: const Text('逐课程设置笔记要求'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SizedBox(
            height: 480,
            child: ListView(
              children: c.courses.map((row) {
                final course = Json.from(row['course'] as Map);
                return ListTile(
                  title: Text('${course['name']}'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute<void>(
                        builder: (_) => RecordingCoursePage(course: course),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ),
    ],
    _ => [
      if (tasks.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无任务。录音上传完成后，可在这里查看转写与笔记任务。'),
        ),
      ...tasks.reversed
          .take(100)
          .map(
            (task) => Card(
              child: ListTile(
                title: Text(
                  '${taskLabels[task['kind']] ?? task['kind']} · ${taskLabels[task['status']] ?? task['status']}',
                ),
                subtitle: Text(
                  '${task['recording_id']}\n${task['error'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => perform(() async {
                    await c.api('POST', '/tasks/${task['id']}/$action', {});
                    await load();
                  }),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'start', child: Text('开始 / 继续')),
                    PopupMenuItem(value: 'stop', child: Text('停止')),
                    PopupMenuItem(value: 'retry', child: Text('重试')),
                  ],
                ),
              ),
            ),
          ),
    ],
  };
}

class RecordingCoursePage extends StatefulWidget {
  const RecordingCoursePage({super.key, required this.course});
  final Json course;
  @override
  State<RecordingCoursePage> createState() => _RecordingCoursePageState();
}

class _RecordingCoursePageState extends State<RecordingCoursePage> {
  final c = RecordingController.instance;
  late Json course;
  List<Json> remoteRecords = [];
  List<Json> get records => mergeRecordingSources(
    remoteRecords,
    c.localRecordings,
    '${course['id']}',
  );
  Timer? refreshTimer;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    course = {...widget.course};
    c.addListener(localUpdate);
    unawaited(
      run(() async {
        final cached = await c.cachedRecordings('${course['id']}');
        if (mounted) setState(() => remoteRecords = cached);
        await c.refreshLocalRecordings();
        await load();
      }),
    );
    refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(run(load)),
    );
  }

  void localUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    c.removeListener(localUpdate);
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final rows = await c.fetchRecordings('${course['id']}');
      if (mounted) {
        setState(() {
          remoteRecords = rows;
          error = null;
        });
      }
    } finally {
      loading = false;
    }
  }

  Future<void> run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
        });
      }
    }
  }

  Future<void> patch(Json values) async {
    final out = await c.updateCourse('${course['id']}', values);
    if (mounted) {
      setState(() {
        course = Json.from(out as Map);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${course['name']}'),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => run(load)),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (error != null) Text(error!),
        CourseOverview(
          course: course,
          count: records.length,
          seconds: records.fold<num>(
            0,
            (n, r) => n + (r['samples'] as num? ?? 0) / 16000,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Icon(Icons.tune, color: CourseStyle(course).color),
            title: const Text('课程设置'),
            subtitle: const Text('教师信息、自动录音与专属笔记提示词'),
            children: [
              ListTile(
                title: const Text('课程信息'),
                subtitle: Text('${course['teachers'] ?? ''}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => run(() async {
                  final text = await editRecordingText(
                    context,
                    '课程名称',
                    '${course['name']}',
                  );
                  if (text != null) await patch({'name': text});
                }),
              ),
              ListTile(
                title: const Text('教师'),
                subtitle: Text('${course['teachers'] ?? ''}'),
                onTap: () => run(() async {
                  final text = await editRecordingText(
                    context,
                    '教师',
                    '${course['teachers'] ?? ''}',
                  );
                  if (text != null) await patch({'teachers': text});
                }),
              ),
              SwitchListTile(
                title: const Text('此课程自动录音'),
                value: course['auto_record'] == true,
                onChanged: course['id'] == 'misc'
                    ? null
                    : (v) => run(() => patch({'auto_record': v})),
              ),
              ListTile(
                title: const Text('课程笔记提示词'),
                subtitle: Text('${course['prompt'] ?? '未设置'}', maxLines: 3),
                onTap: () => run(() async {
                  final text = await editRecordingText(
                    context,
                    '课程笔记提示词',
                    '${course['prompt'] ?? ''}',
                    multiline: true,
                  );
                  if (text != null) await patch({'prompt': text});
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('课堂记录', style: Theme.of(context).textTheme.titleLarge),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('还没有课堂录音，开始录制或上传一份 WAV 吧')),
          ),
        const SizedBox(height: 12),
        RecordingArchiveGrid(
          children: records
              .map(
                (r) => RecordingSyncCard(
                  row: r,
                  workerRunning: c.status['sync_running'] == true,
                  onUpload: () => run(() => c.uploadRecording('${r['id']}')),
                  onOpen: recordingOnServer(r)
                      ? () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RecordingDetailPage(record: r),
                            ),
                          );
                          await run(load);
                        }
                      : null,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: const Text('上传 WAV 录音'),
          onPressed: () => run(() async {
            final file = await openFile(
              acceptedTypeGroups: [
                const XTypeGroup(label: 'WAV', extensions: ['wav']),
              ],
            );
            if (file == null) return;
            final record = await c.api('POST', '/recordings', {
              'course_id': course['id'],
              'title': file.name,
            });
            final request = http.StreamedRequest(
              'PUT',
              Uri.parse('${c.baseUrl}/api/v1/recordings/${record['id']}/audio'),
            );
            request.headers['X-API-Key'] = c.apiKey;
            request.headers['Content-Type'] = 'audio/wav';
            final future = request.send();
            await request.sink.addStream(file.openRead());
            await request.sink.close();
            final response = await http.Response.fromStream(await future);
            if (response.statusCode != 200) throw StateError(response.body);
            await load();
          }),
        ),
        if (course['id'] != 'misc')
          TextButton(
            onPressed: () => run(() async {
              if (!await confirmRecordingDelete(
                context,
                '将删除此课程及 ${records.length} 次录音、转写和笔记。',
              )) {
                return;
              }
              await c.api('DELETE', '/courses/${course['id']}?cascade=true');
              if (context.mounted) Navigator.pop(context);
            }),
            child: const Text('删除课程与关联数据'),
          ),
      ],
    ),
  );
}

class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({super.key, required this.record});
  final Json record;
  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  final c = RecordingController.instance;
  List<Json> segments = [];
  List<Json> notes = [];
  List<Json> transcriptionTasks = [];
  bool submittingTranscription = false;
  bool refreshing = false;
  String? error;
  bool playing = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    c.addListener(update);
    unawaited(run(load));
    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(run(load)),
    );
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    c.removeListener(update);
    unawaited(c.command('stopPlayback').catchError((Object _) {}));
    super.dispose();
  }

  Future<void> run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
        });
      }
    }
  }

  Future<void> load() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final transcript =
          await c.api('GET', '/recordings/${widget.record['id']}/transcript')
              as List? ??
          [];
      final result =
          await c.api('GET', '/notes?recording_id=${widget.record['id']}')
              as List? ??
          [];
      final tasks = await c.api('GET', '/tasks') as List? ?? [];
      if (mounted) {
        setState(() {
          segments = transcript.map((e) => Json.from(e as Map)).toList();
          notes = result.map((e) => Json.from(e as Map)).toList();
          transcriptionTasks =
              tasks
                  .map((e) => Json.from(e as Map))
                  .where(
                    (t) =>
                        t['recording_id'] == widget.record['id'] &&
                        t['kind'] == 'transcribe',
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      '${b['created_at']}'.compareTo('${a['created_at']}'),
                );
        });
      }
    } finally {
      refreshing = false;
    }
  }

  bool get transcribing => transcriptionTasks.any(
    (t) => ['queued', 'running', 'stopping'].contains(t['status']),
  );

  Future<void> retranscribe() async {
    if (submittingTranscription || transcribing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新转写这份录音？'),
        content: const Text(
          '服务器将重新识别完整音频和说话人。成功后替换原文及手动修正；已有笔记版本保留，需要时可再点“重新生成笔记”。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始转写'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      submittingTranscription = true;
      error = null;
    });
    try {
      final task = Json.from(
        await c.api('POST', '/tasks', {
              'recording_id': widget.record['id'],
              'kind': 'transcribe',
            })
            as Map,
      );
      if (!mounted) return;
      setState(() => transcriptionTasks.insert(0, task));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已提交重新转写，完成后自动刷新原文')));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => submittingTranscription = false);
    }
  }

  Future<void> play([num seconds = 0]) async {
    await c.command('play', {
      'url': '${c.baseUrl}/api/v1/recordings/${widget.record['id']}/audio',
      'key': c.apiKey,
      'position_ms': (seconds * 1000).toInt(),
    });
    if (mounted) {
      setState(() {
        playing = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.record['title']}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) => run(() async {
              if (action == 'rename') {
                final text = await editRecordingText(
                  context,
                  '录音标题',
                  '${widget.record['title']}',
                );
                if (text != null) {
                  await c.api('PATCH', '/recordings/${widget.record['id']}', {
                    'title': text,
                  });
                  setState(() {
                    widget.record['title'] = text;
                  });
                }
              }
              if (!context.mounted) return;
              if (action == 'delete' &&
                  await confirmRecordingDelete(context, '删除这次录音、转写和笔记？')) {
                await c.api('DELETE', '/recordings/${widget.record['id']}');
                if (context.mounted) Navigator.pop(context);
              }
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('修改标题')),
              PopupMenuItem(value: 'delete', child: Text('删除录音')),
            ],
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: '转写原文'),
            Tab(text: '课堂笔记'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: submittingTranscription || transcribing
                      ? null
                      : retranscribe,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(
                    submittingTranscription
                        ? '正在提交…'
                        : transcribing
                        ? '转写处理中'
                        : '重新转写',
                  ),
                ),
                Text(recordingDate(widget.record['started_at'])),
                if (transcriptionTasks.isNotEmpty)
                  Text(
                    '转写任务：${recordingStateLabel(transcriptionTasks.first['status'] as String?)}',
                  ),
              ],
            ),
          ),
          if (transcriptionTasks.isNotEmpty &&
              '${transcriptionTasks.first['error'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${transcriptionTasks.first['error']}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (widget.record['interrupted'] == true ||
              '${widget.record['capture_error'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '此录音存在中断：${widget.record['capture_error'] ?? '设备或录音进程重启'}',
              ),
            ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          Row(
            children: [
              IconButton(
                onPressed: () => run(() async {
                  if (playing) {
                    await c.command('stopPlayback');
                    setState(() {
                      playing = false;
                    });
                  } else {
                    await play();
                  }
                }),
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
              ),
              Expanded(
                child: Slider(
                  value: ((c.status['player_position'] as num? ?? 0) / 1000)
                      .clamp(
                        0,
                        ((widget.record['samples'] as num? ?? 0) / 16000).clamp(
                          1,
                          double.infinity,
                        ),
                      ),
                  max: ((widget.record['samples'] as num? ?? 0) / 16000)
                      .clamp(1, double.infinity)
                      .toDouble(),
                  onChanged: (v) => run(
                    () =>
                        c.command('seek', {'position_ms': (v * 1000).toInt()}),
                  ),
                ),
              ),
              Text(
                durationLabel((widget.record['samples'] as num? ?? 0) / 16000),
              ),
              const SizedBox(width: 12),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  children: segments
                      .map(
                        (p) => ListTile(
                          title: Text('${p['text']}'),
                          subtitle: Text(
                            '${p['speaker']} · ${durationLabel(p['start'] as num)}',
                          ),
                          onTap: () => run(() => play(p['start'] as num)),
                          trailing: PopupMenuButton<String>(
                            onSelected: (field) => run(() async {
                              final text = await editRecordingText(
                                context,
                                field == 'text' ? '修正原文' : '说话人名称',
                                '${p[field]}',
                                multiline: field == 'text',
                              );
                              if (text != null) {
                                await c.api(
                                  'PATCH',
                                  '/recordings/${widget.record['id']}/transcript/${p['id']}',
                                  {field: text},
                                );
                                await load();
                              }
                            }),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'text', child: Text('修正原文')),
                              PopupMenuItem(
                                value: 'speaker',
                                child: Text('命名说话人'),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => run(() async {
                            await c.api('POST', '/tasks', {
                              'recording_id': widget.record['id'],
                            });
                          }),
                          child: const Text('重新生成笔记'),
                        ),
                        OutlinedButton(
                          onPressed: () => run(() async {
                            final text = await editRecordingText(
                              context,
                              '新建笔记',
                              '',
                              multiline: true,
                            );
                            if (text != null) {
                              await c.api('POST', '/notes', {
                                'recording_id': widget.record['id'],
                                'markdown': text,
                              });
                              await load();
                            }
                          }),
                          child: const Text('手写笔记'),
                        ),
                      ],
                    ),
                    ...notes.reversed.map(
                      (note) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${note['created_at']}${note['edited'] == true ? ' · 已编辑' : ''}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              MarkdownBody(
                                data: '${note['markdown']}',
                                selectable: true,
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => run(() async {
                                      final text = await editRecordingText(
                                        context,
                                        '编辑 Markdown',
                                        '${note['markdown']}',
                                        multiline: true,
                                      );
                                      if (text != null) {
                                        await c.api(
                                          'PATCH',
                                          '/notes/${note['id']}',
                                          {'markdown': text},
                                        );
                                        await load();
                                      }
                                    }),
                                    child: const Text('编辑'),
                                  ),
                                  TextButton(
                                    onPressed: () => run(() async {
                                      if (await confirmRecordingDelete(
                                        context,
                                        '删除此版本笔记？',
                                      )) {
                                        await c.api(
                                          'DELETE',
                                          '/notes/${note['id']}',
                                        );
                                        await load();
                                      }
                                    }),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
