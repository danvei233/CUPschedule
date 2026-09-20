import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_image_storage.dart';
import 'schedule/schedule_repository.dart';

typedef BackgroundImagePersister =
    Future<StoredBackgroundImage> Function(
      XFile source, {
      String? previousPath,
    });
typedef BackgroundImageReader = Future<Uint8List?> Function(String path);
typedef BackgroundImageDeleter = Future<void> Function(String? path);

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
  AppThemeController({
    SharedPreferences? preferences,
    BackgroundImagePersister imagePersister = persistBackgroundImage,
    BackgroundImageReader imageReader = readBackgroundImage,
    BackgroundImageDeleter imageDeleter = deleteBackgroundImage,
  }) : _preferences = preferences,
       _imagePersister = imagePersister,
       _imageReader = imageReader,
       _imageDeleter = imageDeleter;

  static const storageKey = 'app.theme_mode';
  static const backgroundPathKey = 'app.background.path';
  static const backgroundImageOpacityKey = 'app.background.image_opacity';
  static const backgroundMaskColorKey = 'app.background.mask_color';
  static const backgroundMaskOpacityKey = 'app.background.mask_opacity';
  static const backgroundCourseOpacityKey = 'app.background.course_opacity';

  SharedPreferences? _preferences;
  final BackgroundImagePersister _imagePersister;
  final BackgroundImageReader _imageReader;
  final BackgroundImageDeleter _imageDeleter;
  BlackbookThemePreference _preference = BlackbookThemePreference.system;
  AppBackgroundSettings _background = AppBackgroundSettings.defaults;
  Uint8List? _backgroundImageBytes;

  BlackbookThemePreference get preference => _preference;
  ThemeMode get themeMode => _preference.themeMode;
  AppBackgroundSettings get background => _background;
  Uint8List? get backgroundImageBytes => _backgroundImageBytes;
  bool get hasBackgroundImage => _backgroundImageBytes != null;

  Future<void> load() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    _preference = BlackbookThemePreference.fromStorage(
      preferences.getString(storageKey),
    );
    _background = AppBackgroundSettings(
      imagePath: preferences.getString(backgroundPathKey),
      imageOpacity:
          preferences.getDouble(backgroundImageOpacityKey) ??
          AppBackgroundSettings.defaults.imageOpacity,
      maskColor: Color(
        preferences.getInt(backgroundMaskColorKey) ??
            AppBackgroundSettings.defaults.maskColor.toARGB32(),
      ),
      maskOpacity:
          preferences.getDouble(backgroundMaskOpacityKey) ??
          AppBackgroundSettings.defaults.maskOpacity,
      courseCardOpacity:
          preferences.getDouble(backgroundCourseOpacityKey) ??
          AppBackgroundSettings.defaults.courseCardOpacity,
    ).normalized();
    final imagePath = _background.imagePath;
    if (imagePath != null) {
      _backgroundImageBytes = await _imageReader(imagePath);
      if (_backgroundImageBytes == null) {
        _background = _background.copyWith(clearImagePath: true);
        await preferences.remove(backgroundPathKey);
      }
    }
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

  Future<void> setBackgroundImage(XFile source) async {
    final stored = await _imagePersister(
      source,
      previousPath: _background.imagePath,
    );
    _backgroundImageBytes = stored.bytes;
    _background = _background.copyWith(imagePath: stored.path);
    if (_preference != BlackbookThemePreference.dark) {
      await setPreference(BlackbookThemePreference.dark);
    } else {
      notifyListeners();
    }
    await _saveBackground();
  }

  Future<void> clearBackgroundImage() async {
    final previousPath = _background.imagePath;
    _backgroundImageBytes = null;
    _background = _background.copyWith(clearImagePath: true);
    notifyListeners();
    await _imageDeleter(previousPath);
    await _saveBackground();
  }

  void previewBackgroundImageOpacity(double value) {
    _background = _background.copyWith(imageOpacity: value).normalized();
    notifyListeners();
  }

  Future<void> setBackgroundImageOpacity(double value) async {
    previewBackgroundImageOpacity(value);
    await _saveBackground();
  }

  void previewBackgroundMaskOpacity(double value) {
    _background = _background.copyWith(maskOpacity: value).normalized();
    notifyListeners();
  }

  Future<void> setBackgroundMaskOpacity(double value) async {
    previewBackgroundMaskOpacity(value);
    await _saveBackground();
  }

  Future<void> setBackgroundMaskColor(Color value) async {
    _background = _background.copyWith(maskColor: value.withValues(alpha: 1));
    notifyListeners();
    await _saveBackground();
  }

  void previewBackgroundCourseCardOpacity(double value) {
    _background = _background.copyWith(courseCardOpacity: value).normalized();
    notifyListeners();
  }

  Future<void> setBackgroundCourseCardOpacity(double value) async {
    previewBackgroundCourseCardOpacity(value);
    await _saveBackground();
  }

  Future<void> _saveBackground() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final path = _background.imagePath;
    if (path == null) {
      await preferences.remove(backgroundPathKey);
    } else {
      await preferences.setString(backgroundPathKey, path);
    }
    await preferences.setDouble(
      backgroundImageOpacityKey,
      _background.imageOpacity,
    );
    await preferences.setInt(
      backgroundMaskColorKey,
      _background.maskColor.toARGB32(),
    );
    await preferences.setDouble(
      backgroundMaskOpacityKey,
      _background.maskOpacity,
    );
    await preferences.setDouble(
      backgroundCourseOpacityKey,
      _background.courseCardOpacity,
    );
  }
}

class AppBackgroundSettings {
  const AppBackgroundSettings({
    required this.imagePath,
    required this.imageOpacity,
    required this.maskColor,
    required this.maskOpacity,
    required this.courseCardOpacity,
  });

  static const defaults = AppBackgroundSettings(
    imagePath: null,
    imageOpacity: 1,
    maskColor: Color(0xFF000000),
    maskOpacity: 0.18,
    courseCardOpacity: 0.58,
  );

  final String? imagePath;
  final double imageOpacity;
  final Color maskColor;
  final double maskOpacity;
  final double courseCardOpacity;

  AppBackgroundSettings copyWith({
    String? imagePath,
    double? imageOpacity,
    Color? maskColor,
    double? maskOpacity,
    double? courseCardOpacity,
    bool clearImagePath = false,
  }) {
    return AppBackgroundSettings(
      imagePath: clearImagePath ? null : imagePath ?? this.imagePath,
      imageOpacity: imageOpacity ?? this.imageOpacity,
      maskColor: maskColor ?? this.maskColor,
      maskOpacity: maskOpacity ?? this.maskOpacity,
      courseCardOpacity: courseCardOpacity ?? this.courseCardOpacity,
    );
  }

  AppBackgroundSettings normalized() {
    return copyWith(
      imageOpacity: imageOpacity.clamp(0, 1),
      maskOpacity: maskOpacity.clamp(0, 1),
      courseCardOpacity: courseCardOpacity.clamp(0.2, 0.95),
    );
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
