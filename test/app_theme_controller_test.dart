import 'package:blackbook/src/app_theme_controller.dart';
import 'package:blackbook/src/schedule/schedule_repository.dart';
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
