import 'dart:async';
import 'package:flutter/material.dart';

class AudioModelPanel extends StatefulWidget {
  const AudioModelPanel({super.key, required this.control});
  final Future<Map<String, dynamic>> Function(String action) control;

  @override
  State<AudioModelPanel> createState() => _AudioModelPanelState();
}

class _AudioModelPanelState extends State<AudioModelPanel> {
  Map<String, dynamic>? status;
  String? action;
  String? error;
  DateTime? updated;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    unawaited(run('status'));
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (action == null) unawaited(run('status'));
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> run(String value) async {
    if (action != null) return;
    setState(() {
      action = value;
    });
    try {
      final result = await widget.control(value);
      if (!mounted) return;
      setState(() {
        status = result;
        updated = DateTime.now();
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          action = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = status?['loaded'] == true;
    final busy = status?['busy'] == true;
    final modelError = '${status?['error'] ?? ''}';
    final failed = error != null || modelError.isNotEmpty;
    final title = error != null
        ? '连接失败'
        : modelError.isNotEmpty
        ? '模型异常'
        : status == null
        ? '正在查询模型'
        : busy
        ? '正在处理音频'
        : loaded
        ? '模型已就绪'
        : '模型未加载';
    final color = failed
        ? Theme.of(context).colorScheme.error
        : loaded
        ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.tealAccent.shade400
              : Colors.teal.shade700)
        : Theme.of(context).colorScheme.primary;
    const labels = {
      'status': '刷新状态',
      'load': '加载模型',
      'unload': '卸载模型',
      'reload': '重新加载',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : loaded
                      ? Icons.graphic_eq
                      : Icons.memory_outlined,
                  color: color,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        status == null
                            ? '连接音频服务器以获取状态'
                            : 'faster-whisper · ${status?['model'] ?? '未知型号'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      status?['mock'] == true
                          ? Icons.science_outlined
                          : Icons.dns_outlined,
                      size: 18,
                    ),
                    label: Text(status?['mock'] == true ? '模拟模式' : '真实模型服务'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.mic_none, size: 18),
                    label: Text('${status?['sessions'] ?? 0} 个实时会话'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(loaded ? '可接收转写请求；处理进度请查看下方任务列表。' : '加载模型后即可转写，已保存的音频不受影响。'),
            ],
            if (failed) ...[
              const SizedBox(height: 12),
              Text(
                error != null
                    ? '无法获取最新状态，请检查服务地址、密钥及服务是否启动。'
                    : '模型加载或推理失败，请检查服务端环境。',
                style: TextStyle(color: color),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('查看错误详情'),
                children: [SelectableText(error ?? modelError)],
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(action == 'status' ? '正在查询…' : '${labels[action]}中，请稍候…'),
              if (action == 'load' || action == 'reload')
                const Text('首次加载可能需要下载模型，服务端暂未提供下载百分比。'),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in labels.entries)
                  OutlinedButton.icon(
                    onPressed:
                        action != null ||
                            (entry.key != 'status' && busy) ||
                            (entry.key == 'load' && loaded) ||
                            (entry.key == 'unload' && !loaded)
                        ? null
                        : () => run(entry.key),
                    icon: Icon(
                      {
                        'status': Icons.refresh,
                        'load': Icons.play_arrow,
                        'unload': Icons.stop,
                        'reload': Icons.restart_alt,
                      }[entry.key],
                      size: 18,
                    ),
                    label: Text(entry.value),
                  ),
              ],
            ),
            if (updated != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${error != null ? '上次成功查询' : '更新于'} ${updated!.hour.toString().padLeft(2, '0')}:${updated!.minute.toString().padLeft(2, '0')}:${updated!.second.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
