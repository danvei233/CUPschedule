# Platform Support

## Widgets

- Android: supported. Native AppWidget shows today's remaining courses, follows theme, and can use fixed display settings.
- iOS: supported through WidgetKit. The Flutter app exports a compact widget payload to the App Group `group.cn.blackbook.blackbook`; the WidgetKit extension reads it and refreshes timelines. Real device/TestFlight/App Store builds need a matching Apple Team, bundle id, App Group capability, and provisioning profiles.
- HarmonyOS/OpenHarmony: main app project is present under `ohos/` and is intended for the OpenHarmony Flutter SDK. Standard Flutter stable still does not provide `flutter build hap`. A basic home-screen FormExtensionAbility is present and opens the app; live schedule data sync for the HarmonyOS card still needs a native bridge.

## Release Builds

GitHub Actions build artifacts when a GitHub Release is published:

- Android APK: `arm64-v8a`, `armeabi-v7a`, `x86_64`, universal, and release AAB.
- Windows: `x64` zip.
- iOS: unsigned app archive zip; signing/export still requires Apple team certificates/profiles.
- HarmonyOS/OpenHarmony: CI job uses the OpenHarmony Flutter SDK when OHOS SDK/toolchain is configured. For hosted runners, set `OHOS_SDK_HOME`/`DEVECO_SDK_HOME` or provide `OHOS_SDK_ARCHIVE_URL`.
