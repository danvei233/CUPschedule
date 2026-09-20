import 'package:blackbook/src/recording/course_cards.dart';
import 'package:blackbook/src/recording/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rows = List.generate(
    4,
    (i) => <String, dynamic>{
      'course': {'id': 'course-$i', 'name': '高等数学 $i', 'teachers': '张老师'},
      'recording_count': 3,
      'duration_seconds': 7200,
    },
  );
  for (final width in [360.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('course cards adapt at $width in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Json? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CourseGrid(rows: rows, onOpen: (c) => opened = c),
                ),
              ),
            ),
          ),
        );
        final first = tester.getTopLeft(find.byType(CourseCard).at(0));
        final second = tester.getTopLeft(find.byType(CourseCard).at(1));
        if (width > 1000) {
          expect(first.dy, second.dy);
          expect(second.dx, greaterThan(first.dx));
        } else {
          expect(second.dy, greaterThan(first.dy));
        }
        await tester.tap(find.text('高等数学 0'));
        expect(opened?['id'], 'course-0');
        expect(find.text('3 节录音'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
