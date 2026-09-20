import 'dart:async';
import 'package:blackbook/src/recording/audio_model_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders model status and waits for load confirmation', (
    tester,
  ) async {
    final loading = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioModelPanel(
            control: (action) async => action == 'load'
                ? loading.future
                : {
                    'loaded': false,
                    'busy': false,
                    'mock': true,
                    'model': 'large-v3-turbo',
                    'sessions': 0,
                    'error': '',
                  },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('模型未加载'), findsOneWidget);
    expect(find.text('模拟模式'), findsOneWidget);
    expect(find.textContaining('"loaded"'), findsNothing);
    await tester.tap(find.text('加载模型'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('模型已就绪'), findsNothing);
    loading.complete({
      'loaded': true,
      'busy': false,
      'mock': false,
      'sessions': 2,
      'model': 'large-v3-turbo',
    });
    await tester.pump();
    expect(find.text('模型已就绪'), findsOneWidget);
    expect(find.text('2 个实时会话'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connection failure displays readable retry state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioModelPanel(
            control: (_) async => throw StateError('HTTP 502'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('刷新状态'), findsOneWidget);
    expect(find.text('查看错误详情'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
