import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'schedule/schedule_repository.dart';

enum BlackbookThemePreference {
  system('system', ThemeMode.system, '自动', Icons.brightness_auto_outlined),
  light('light', ThemeMode.light, '亮色', Icons.light_mode_outlined),
  dark('dark', ThemeMode.dark, '暗色', Icons.dark_mode_outlined);

  const BlackbookThemePreference(
    this.storageValue,
    this.themeMode,
    this.label,
    this.icon,
  );

  final String storageValue;
  final ThemeMode themeMode;
  final String label;
  final IconData icon;

  BlackbookThemePreference get next {
    return switch (this) {
      BlackbookThemePreference.system => BlackbookThemePreference.light,
      BlackbookThemePreference.light => BlackbookThemePreference.dark,
      BlackbookThemePreference.dark => BlackbookThemePreference.system,
    };
  }

  static BlackbookThemePreference fromStorage(String? value) {
    for (final preference in values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return BlackbookThemePreference.system;
  }
}

class AppThemeController extends ChangeNotifier {
  AppThemeController({SharedPreferences? preferences})
    : _preferences = preferences;

  static const storageKey = 'app.theme_mode';

  SharedPreferences? _preferences;
  BlackbookThemePreference _preference = BlackbookThemePreference.system;

  BlackbookThemePreference get preference => _preference;
  ThemeMode get themeMode => _preference.themeMode;

  Future<void> load() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    _preference = BlackbookThemePreference.fromStorage(
      preferences.getString(storageKey),
    );
    await ScheduleWidgetBridge.setThemePreference(_preference.storageValue);
    notifyListeners();
  }

  Future<void> setPreference(BlackbookThemePreference preference) async {
    if (_preference == preference) {
      return;
    }
    _preference = preference;
    notifyListeners();
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    await preferences.setString(storageKey, preference.storageValue);
    await ScheduleWidgetBridge.setThemePreference(preference.storageValue);
    await ScheduleWidgetBridge.refreshTodayClasses();
  }

  Future<void> cycle() {
    return setPreference(_preference.next);
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing from the widget tree');
    return scope!.notifier!;
  }

  static AppThemeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppThemeScope>()
        ?.notifier;
  }
}
