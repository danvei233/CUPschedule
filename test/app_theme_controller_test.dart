import 'dart:typed_data';

import 'package:blackbook/src/app_theme_controller.dart';
import 'package:blackbook/src/background_image_storage.dart';
import 'package:blackbook/src/schedule/schedule_repository.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists the selected app theme mode', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppThemeController();
    await controller.load();

    expect(controller.preference, BlackbookThemePreference.system);
    expect(controller.themeMode, ThemeMode.system);

    await controller.setPreference(BlackbookThemePreference.dark);
    expect(controller.preference, BlackbookThemePreference.dark);

    final restored = AppThemeController();
    await restored.load();
    expect(restored.preference, BlackbookThemePreference.dark);
    expect(restored.themeMode, ThemeMode.dark);
  });

  test('persists and clears custom background settings', () async {
    SharedPreferences.setMockInitialValues({});
    String? deletedPath;
    final controller = AppThemeController(
      imagePersister: (source, {previousPath}) async {
        return StoredBackgroundImage(
          path: 'app/background.png',
          bytes: await source.readAsBytes(),
        );
      },
      imageReader: (path) async =>
          path == 'app/background.png' ? Uint8List.fromList([1, 2, 3]) : null,
      imageDeleter: (path) async => deletedPath = path,
    );
    await controller.load();
    await controller.setBackgroundImage(
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'background.png'),
    );
    await controller.setBackgroundImageOpacity(0.65);
    await controller.setBackgroundMaskColor(const Color(0xFF245B4A));
    await controller.setBackgroundMaskOpacity(0.4);
    await controller.setBackgroundCourseCardOpacity(0.52);

    expect(controller.hasBackgroundImage, isTrue);
    expect(controller.background.imagePath, 'app/background.png');
    expect(controller.preference, BlackbookThemePreference.dark);

    final restored = AppThemeController(
      imageReader: (path) async => Uint8List.fromList([1, 2, 3]),
    );
    await restored.load();
    expect(restored.hasBackgroundImage, isTrue);
    expect(restored.background.imageOpacity, 0.65);
    expect(restored.background.maskColor, const Color(0xFF245B4A));
    expect(restored.background.maskOpacity, 0.4);
    expect(restored.background.courseCardOpacity, 0.52);

    await controller.clearBackgroundImage();
    expect(controller.hasBackgroundImage, isFalse);
    expect(controller.background.imagePath, isNull);
    expect(deletedPath, 'app/background.png');
  });

  test('persists today widget fixed display settings', () async {
    SharedPreferences.setMockInitialValues({});
    const store = TodayWidgetDisplaySettingsStore();

    await store.save(
      TodayWidgetDisplaySettings(
        mode: TodayWidgetContentMode.fixed,
        fixedDate: DateTime(2026, 7, 2),
        fixedTime: const TimeOfDay(hour: 9, minute: 35),
      ),
    );

    final restored = await store.load();
    expect(restored.mode, TodayWidgetContentMode.fixed);
    expect(restored.fixedDateText, '2026-07-02');
    expect(restored.fixedTimeText, '09:35');
  });
}
