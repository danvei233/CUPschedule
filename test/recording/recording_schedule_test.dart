import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blackbook/src/recording/recording_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'extension and automatic capture are off by default; explicit toggle persists',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      SharedPreferences.setMockInitialValues({});
      final controller = RecordingController.instance;
      await controller.load();
      expect(controller.enabled, isFalse);
      expect(controller.autoRecord, isFalse);
      await controller.setEnabled(true);
      expect(
        (await SharedPreferences.getInstance()).getBool('recording.enabled'),
        isTrue,
      );
      await controller.setEnabled(false);
      expect(
        (await SharedPreferences.getInstance()).getBool('recording.enabled'),
        isFalse,
      );
    },
  );
  RecordingSlot slot(
    String course,
    int hour,
    int minute,
    int endHour,
    int endMinute,
    int unit,
  ) => RecordingSlot(
    course,
    DateTime(2026, 9, 21, hour, minute),
    DateTime(2026, 9, 21, endHour, endMinute),
    unit,
    unit,
  );
  test('adjacent same-course periods merge across short breaks only', () {
    final rows = mergeRecordingSlots([
      slot('a', 8, 0, 8, 45, 1),
      slot('a', 8, 55, 9, 40, 2),
      slot('a', 13, 0, 13, 45, 3),
      slot('b', 13, 55, 14, 40, 4),
    ], 30);
    expect(rows.length, 3);
    expect(rows.first.end, DateTime(2026, 9, 21, 9, 40));
    expect(
      rows.first.toJson()['start_ms'],
      DateTime(2026, 9, 21, 8).millisecondsSinceEpoch,
    );
  });
  test('nonadjacent periods never merge and source slots are not mutated', () {
    final first = slot('a', 8, 0, 8, 45, 1);
    expect(
      mergeRecordingSlots([first, slot('a', 8, 55, 9, 40, 3)], 30).length,
      2,
    );
    mergeRecordingSlots([first, slot('a', 8, 55, 9, 40, 2)], 30);
    expect(first.endUnit, 1);
  });
  test('stable UUID format and distinct namespace', () {
    expect(recordingUUID('semester|lesson'), recordingUUID('semester|lesson'));
    expect(
      recordingUUID('semester|lesson'),
      isNot(recordingUUID('other|lesson')),
    );
    expect(
      recordingUUID('semester|lesson'),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
