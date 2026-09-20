import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recording_controller.dart';

String recorderClock(num seconds) {
  final value = seconds.toInt().clamp(0, 9999999);
  final minutes = (value ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(value % 60).toString().padLeft(2, '0')}';
}

/// A reading-first recording surface; controls stay visible while text scrolls.
class LiveRecorder extends StatefulWidget {
  const LiveRecorder({
    super.key,
    required this.controller,
    required this.busy,
    required this.onCommand,
    required this.onRetry,
  });
  final RecordingController controller;
  final bool busy;
  final ValueChanged<String> onCommand;
  final VoidCallback onRetry;

  @override
  State<LiveRecorder> createState() => _LiveRecorderState();
}

class _LiveRecorderState extends State<LiveRecorder> {
  final scroll = ScrollController();
  bool following = true;
  bool largeText = false;
  String lastText = '';

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void follow() {
    setState(() => following = true);
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束这次录音？'),
        content: const Text('录音会保存在设备上。上传完成后，服务器将校正转写并整理笔记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续录音'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束并整理'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onCommand('stop');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.status;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xff181c23);
    final secondary = dark ? const Color(0xffbfc6d2) : const Color(0xff626b78);
    final accent = dark ? const Color(0xffa8c7ff) : const Color(0xff245cd6);
    final paused = s['paused'] == true;
    final elapsed = recorderClock(s['duration_seconds'] as num? ?? 0);
    final pending =
        ((s['chunks'] as num? ?? 0) - (s['acked'] as num? ?? -1) - 1).clamp(
          0,
          999999,
        );
    final course = c.courses
        .map((r) => r['course'] as Map)
        .where((r) => r['id'] == s['course_id'])
        .firstOrNull;
    final title = course?['name'] ?? '新录音';
    final started = DateTime.tryParse('${s['started_at']}')?.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    final date = started == null
        ? '本机录音'
        : '${two(started.month)}-${two(started.day)}  ${two(started.hour)}:${two(started.minute)}';
    final task = c.liveTask;
    final problem = [
      s['error'],
      s['upload_error'],
      task?['error'],
      c.streamError,
    ].where((v) => v != null && '$v'.isNotEmpty).map((v) => '$v').firstOrNull;
    final configured = c.baseUrl.isNotEmpty && c.apiKey.isNotEmpty;
    final state = !configured
        ? '未连接后端 · 音频保存在本机'
        : problem != null
        ? '转写暂不可用 · 录音仍保存在本机'
        : !c.streamConnected
        ? '正在连接转写服务'
        : task?['status'] == 'stopped'
        ? '实时转写任务已停止'
        : task?['status'] == 'running'
        ? '正在识别语音'
        : '实时转写已连接';
    final fingerprint =
        '${s['id']}|${c.transcript.map((p) => '${p['id']}:${p['text']}').join('|')}';
    if (lastText != fingerprint) {
      lastText = fingerprint;
      if (following) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && following && scroll.hasClients) {
            scroll.animateTo(
              scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
    return ColoredBox(
      color: dark ? const Color(0xff14171d) : Colors.white,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq,
                    color: paused ? secondary : accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    elapsed,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: secondary.withValues(alpha: .3),
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      child: Text('中文 · 转写', style: TextStyle(color: ink)),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '录音选项',
                    iconColor: ink,
                    onSelected: (value) async {
                      if (value == 'size') {
                        setState(() => largeText = !largeText);
                      }
                      if (value == 'retry') widget.onRetry();
                      if (value == 'copy') {
                        await Clipboard.setData(
                          ClipboardData(
                            text: c.transcript
                                .map(
                                  (p) =>
                                      '${p['speaker']}  ${recorderClock(p['start'] as num? ?? 0)}\n${p['text']}',
                                )
                                .join('\n\n'),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制转写文字')),
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'size',
                        child: Text(largeText ? '标准字号' : '放大文字'),
                      ),
                      PopupMenuItem(
                        value: 'copy',
                        enabled: c.transcript.isNotEmpty,
                        child: const Text('复制转写文字'),
                      ),
                      PopupMenuItem(
                        value: 'retry',
                        enabled: !widget.busy,
                        child: const Text('重试上传与转写'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: secondary.withValues(alpha: .15)),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (event) {
                      if (event is ScrollUpdateNotification &&
                          event.dragDetails != null) {
                        final nearEnd = event.metrics.extentAfter < 60;
                        if (following != nearEnd) {
                          setState(() => following = nearEnd);
                        }
                      }
                      return false;
                    },
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 80),
                      children: [
                        Text(
                          '$title',
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            _Meta(
                              icon: Icons.calendar_today_outlined,
                              text: date,
                              color: secondary,
                            ),
                            _Meta(
                              icon: Icons.school_outlined,
                              text:
                                  course?['teachers']?.toString().isNotEmpty ==
                                      true
                                  ? '${course!['teachers']}'
                                  : '课堂记录',
                              color: secondary,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Divider(
                            color: secondary.withValues(alpha: .15),
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '实时文字',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: secondary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${c.transcript.length} 段',
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (c.transcript.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  paused
                                      ? Icons.pause_circle_outline
                                      : Icons.spatial_audio_off_outlined,
                                  color: accent,
                                  size: 32,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  paused ? '录音已暂停' : '正在聆听，文字会在这里出现',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: ink,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  !configured
                                      ? '请在设置中填写后端地址和密钥，连接后重试上传。'
                                      : '音频上传并完成识别后，会按说话人逐段显示。首段结果需要等待服务端处理。',
                                  style: TextStyle(
                                    height: 1.8,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...c.transcript.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: .12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.person_outline,
                                        size: 17,
                                        color: accent,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${p['speaker'] ?? '说话人'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      recorderClock(p['start'] as num? ?? 0),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: secondary,
                                      ),
                                    ),
                                    if (p['final'] != true)
                                      Text(
                                        ' · 识别中',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: secondary,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SelectableText(
                                  '${p['text'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: largeText ? 24 : 19,
                                    height: 1.85,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!following)
                    Positioned(
                      bottom: 12,
                      right: 24,
                      child: FilledButton.tonalIcon(
                        onPressed: follow,
                        icon: const Icon(Icons.south, size: 16),
                        label: const Text('回到最新文字'),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xff1b2029) : const Color(0xfff7f9fc),
                border: Border(
                  top: BorderSide(color: secondary.withValues(alpha: .15)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LevelMeter(
                        level: paused
                            ? 0
                            : (s['level'] as num? ?? 0).toDouble(),
                        color: accent,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$elapsed  ${paused ? '已暂停' : '录音中'}',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$state${pending > 0 ? ' · 待上传 $pending 块' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('转写状态'),
                            content: SingleChildScrollView(
                              child: SelectableText(problem),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        ),
                        child: Text(
                          problem,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.error),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        tooltip: '重试上传与转写',
                        onPressed: widget.busy ? null : widget.onRetry,
                        icon: const Icon(Icons.sync),
                      ),
                      SizedBox(
                        width: 150,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: dark
                                ? const Color(0xff12264a)
                                : Colors.white,
                          ),
                          onPressed: widget.busy
                              ? null
                              : () => widget.onCommand(
                                  paused ? 'resume' : 'pause',
                                ),
                          icon: Icon(
                            paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 28,
                          ),
                          label: Text(paused ? '继续录音' : '暂停录音'),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: '结束并整理',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(52, 52),
                          foregroundColor: ink,
                        ),
                        onPressed: widget.busy ? null : stop,
                        icon: const Icon(Icons.stop_rounded, size: 30),
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
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 7),
      Flexible(
        child: Text(text, style: TextStyle(color: color, fontSize: 14)),
      ),
    ],
  );
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.color});
  final double level;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        7,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 3,
          height: 4 + (24 - (i - 3).abs() * 5) * level.clamp(0, 1),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    ),
  );
}
