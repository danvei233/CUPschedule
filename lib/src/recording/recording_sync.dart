import 'package:flutter/material.dart';
import 'recording_controller.dart';
import 'course_cards.dart';

List<Json> mergeRecordingSources(
  List<Json> remote,
  List<Json> local,
  String course,
) {
  final rows = <String, Json>{
    for (final r in remote) '${r['id']}': {...r, 'remote': true},
  };
  for (final r in local.where((r) => r['course_id'] == course)) {
    final id = '${r['id']}';
    if (r['destination_matches'] == false) {
      rows['local-$id'] = {...r, 'local': r, 'remote': false};
    } else {
      rows[id] = {
        ...r,
        ...?rows[id],
        'samples':
            (r['samples'] as num? ?? 0) > (rows[id]?['samples'] as num? ?? 0)
            ? r['samples']
            : rows[id]?['samples'] ?? r['samples'],
        'local': r,
        'remote': rows[id]?['remote'] == true,
      };
    }
  }
  return rows.values.toList()
    ..sort((a, b) => '${b['started_at']}'.compareTo('${a['started_at']}'));
}

bool recordingOnServer(Json r) =>
    r['local'] is Map && (r['local'] as Map)['destination_matches'] == false
    ? false
    : r['remote'] == true && r['status'] != 'recording';

String recordingSyncLabel(Json row, {bool workerRunning = true}) {
  final local = row['local'] as Map?;
  if (local?['destination_matches'] == false) return '属于其他服务器';
  if (recordingOnServer(row) || local?['uploaded'] == true) return '已上传并校验';
  if (local == null) return '云端音频尚未完整上传';
  if (!workerRunning) return '已保存在本机 · 等待上传';
  switch (local['sync_state']) {
    case 'uploaded':
      return '已上传并校验';
    case 'waiting_config':
      return '等待配置后端';
    case 'waiting_network':
      return '等待网络 · 自动重试';
    case 'failed':
      return '上传失败 · 自动重试';
    case 'verifying':
      return '服务器校验、合并中';
    case 'uploading':
      return '正在上传';
    case 'different_server':
      return '属于其他服务器';
    default:
      return '仅保存在本机';
  }
}

class RecordingSyncCard extends StatelessWidget {
  const RecordingSyncCard({
    super.key,
    required this.row,
    required this.onUpload,
    this.onOpen,
    this.workerRunning = true,
  });
  final Json row;
  final VoidCallback onUpload;
  final VoidCallback? onOpen;
  final bool workerRunning;
  @override
  Widget build(BuildContext context) {
    final local = row['local'] as Map?;
    final uploaded =
        recordingOnServer(row) ||
        (local?['uploaded'] == true && local?['destination_matches'] != false);
    final total = (local?['total_chunks'] as num? ?? 0).toInt();
    final acked = ((local?['acked'] as num? ?? -1).toInt() + 1).clamp(0, total);
    final progress = total == 0 ? 0.0 : acked / total;
    final color = uploaded
        ? Colors.teal
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  uploaded ? Icons.cloud_done_outlined : Icons.phone_android,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${row['title'] ?? '本机录音'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${recordingDate(row['started_at'])} · ${courseDuration((row['samples'] as num? ?? 0) / 16000)}',
            ),
            const SizedBox(height: 12),
            Text(
              recordingSyncLabel(row, workerRunning: workerRunning),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (local != null && !uploaded) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Text(
                '${(progress * 100).floor()}% · 服务器已确认 $acked / $total 块${local['finished'] == true ? '' : ' · 正在录制'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if ('${local['sync_error'] ?? ''}'.isNotEmpty)
                Text(
                  '${local['sync_error']}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
            ],
            if (row['remote'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '转写 / 笔记：${recordingStateLabel(row['status'] as String?)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (local != null && !uploaded)
                  OutlinedButton.icon(
                    onPressed: local['destination_matches'] == false
                        ? null
                        : onUpload,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(
                      local['sync_state'] == 'failed' ? '重试上传' : '立即上传',
                    ),
                  ),
                if (onOpen != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('查看录音'),
                  ),
                if (local != null && row['remote'] != true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '音频保存在设备上，上传完成后可查看转写',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RecordingSyncPage extends StatefulWidget {
  const RecordingSyncPage({super.key});
  @override
  State<RecordingSyncPage> createState() => _RecordingSyncPageState();
}

class _RecordingSyncPageState extends State<RecordingSyncPage> {
  final c = RecordingController.instance;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    c.addListener(update);
    c.refreshLocalRecordings();
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(update);
    super.dispose();
  }

  Future<void> upload(String? id) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (id == null) {
        await c.command('sync');
      } else {
        await c.uploadRecording(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已唤醒上传队列，联网后自动补传')));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('本机录音与同步')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '断网录音保存在本机，恢复联网后自动补传。无后台守护时，重新打开 App 会恢复队列。上传并校验完成后，本机副本保留 7 天。',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : () => upload(null),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('上传全部待同步录音'),
        ),
        if (error != null) Text(error!),
        if (c.localRecordings.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Text('本机暂无录音')),
        RecordingArchiveGrid(
          children: c.localRecordings
              .map(
                (r) => RecordingSyncCard(
                  row: {...r, 'local': r},
                  workerRunning: c.status['sync_running'] == true,
                  onUpload: () => upload('${r['id']}'),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}
