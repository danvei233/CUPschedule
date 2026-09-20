import 'package:blackbook/src/recording/recording_settings_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets('settings categories fit and switch at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => RecordingSettingsLayout(
                selected: selected,
                onSelected: (value) => setState(() => selected = value),
                summaries: const ['后端', '关闭', '服务', '模型', '要求', '暂无任务'],
                busy: false,
                onRefresh: () {},
                children: [Text('当前分类 $selected')],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('提示词').first);
      await tester.pumpAndSettle();
      expect(find.text('当前分类 4'), findsOneWidget);
      expect(find.text('当前分类 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
