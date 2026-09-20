import 'package:blackbook/src/recording/live_recorder.dart';
import 'package:blackbook/src/recording/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replayed events and older revisions cannot overwrite newer text', () {
    final c = RecordingController.forTesting();
    addTearDown(c.dispose);
    Json event(int cursor, int version, String text) => {
      'type': 'segment',
      'cursor': cursor,
      'segment': {
        'id': 'a',
        'version': version,
        'start': 0,
        'end': 4,
        'text': text,
      },
    };
    c.applyTranscriptEvent(event(2, 2, '正确结果'));
    c.applyTranscriptEvent(event(1, 1, '过期事件'));
    c.applyTranscriptEvent(event(3, 1, '过期版本'));
    expect(c.transcript.single['text'], '正确结果');
    c.applyTranscriptEvent({
      'type': 'segment',
      'cursor': 4,
      'segment': {'replace_from': 0},
    });
    c.applyTranscriptEvent(event(5, 3, '校正结果'));
    expect(c.transcript.single['text'], '校正结果');
  });

  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    for (final brightness in Brightness.values) {
      testWidgets('live transcript and fixed controls at $size $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = RecordingController.forTesting();
        addTearDown(c.dispose);
        c.baseUrl = 'http://localhost';
        c.apiKey = 'test';
        c.streamConnected = true;
        c.status = {
          'recording': true,
          'id': 'r',
          'duration_seconds': 42,
          'level': .4,
        };
        c.transcript = [
          {
            'id': 's1',
            'speaker': '说话人 1',
            'start': 2,
            'end': 8,
            'text': '今天我们学习微积分的基本定理。',
            'final': false,
          },
        ];
        String? command;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: LiveRecorder(
                controller: c,
                busy: false,
                onCommand: (v) => command = v,
                onRetry: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('今天我们学习微积分的基本定理。'), findsOneWidget);
        expect(find.text('说话人 1'), findsOneWidget);
        expect(find.text('00:02'), findsOneWidget);
        await tester.tap(find.text('暂停录音'));
        expect(command, 'pause');
        await tester.tap(find.byTooltip('结束并整理'));
        await tester.pumpAndSettle();
        expect(find.text('结束这次录音？'), findsOneWidget);
        expect(command, 'pause');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('failure is visible while recording controls remain available', (
    tester,
  ) async {
    final c = RecordingController.forTesting();
    addTearDown(c.dispose);
    c.baseUrl = 'http://localhost';
    c.apiKey = 'test';
    c.status = {'recording': true};
    c.liveTask = {'status': 'failed', 'error': '音频模型尚未加载'};
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveRecorder(
            controller: c,
            busy: false,
            onCommand: (_) {},
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    expect(find.text('音频模型尚未加载'), findsOneWidget);
    expect(find.text('正在聆听，文字会在这里出现'), findsOneWidget);
    await tester.tap(find.byTooltip('重试上传与转写'));
    expect(retried, isTrue);
  });
}
