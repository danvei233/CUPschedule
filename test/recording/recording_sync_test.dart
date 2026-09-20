import 'package:blackbook/src/recording/recording_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local-only and partial cloud rows merge without losing local duration',
    () {
      final rows = mergeRecordingSources(
        [
          {'id': 'a', 'course_id': 'c', 'status': 'recording', 'samples': 0},
        ],
        [
          {'id': 'a', 'course_id': 'c', 'samples': 16000, 'uploaded': false},
          {'id': 'b', 'course_id': 'c', 'samples': 32000, 'uploaded': false},
        ],
        'c',
      );
      expect(rows.length, 2);
      final a = rows.firstWhere((r) => r['id'] == 'a');
      expect(a['samples'], 16000);
      expect(recordingOnServer(a), isFalse);
      expect(recordingSyncLabel(a), '仅保存在本机');
    },
  );
  test('100% chunks is not a verified complete file', () {
    final row = {
      'id': 'a',
      'local': {
        'total_chunks': 3,
        'acked': 2,
        'sync_state': 'verifying',
        'uploaded': false,
      },
    };
    expect(recordingSyncLabel(row), '服务器校验、合并中');
    expect(recordingOnServer(row), isFalse);
    expect(
      recordingSyncLabel({'remote': true, 'status': 'processing'}),
      '已上传并校验',
    );
  });
  test('another server destination cannot be presented as uploaded here', () {
    final row = {
      'local': {'uploaded': true, 'destination_matches': false},
      'remote': false,
    };
    expect(recordingSyncLabel(row), '属于其他服务器');
    expect(recordingOnServer(row), isFalse);
  });
  testWidgets('offline row shows progress and manual upload', (tester) async {
    var uploaded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingSyncCard(
            row: {
              'title': '离线课堂',
              'samples': 16000,
              'local': {
                'total_chunks': 4,
                'acked': 1,
                'sync_state': 'waiting_network',
                'finished': true,
              },
            },
            onUpload: () => uploaded = true,
          ),
        ),
      ),
    );
    expect(find.text('等待网络 · 自动重试'), findsOneWidget);
    expect(find.text('50% · 服务器已确认 2 / 4 块'), findsOneWidget);
    await tester.tap(find.text('立即上传'));
    expect(uploaded, isTrue);
    expect(tester.takeException(), isNull);
  });
}
