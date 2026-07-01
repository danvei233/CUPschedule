import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupIdentifier = "group.cn.blackbook.blackbook"
  private let widgetChannelName = "blackbook/today_classes_widget"
  private let widgetPayloadKey = "today_widget_payload"
  private let themePreferenceKey = "app.theme.preference"
  private let widgetModeKey = "widget.today.content_mode"
  private let widgetFixedDateKey = "widget.today.fixed_date"
  private let widgetFixedTimeKey = "widget.today.fixed_time"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: widgetChannelName,
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { [weak self] call, result in
        self?.handleWidgetMethodCall(call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleWidgetMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let defaults = UserDefaults(suiteName: appGroupIdentifier)
    switch call.method {
    case "refresh":
      saveWidgetPayload(arguments?["payload"], defaults: defaults)
      reloadWidgets()
      result(nil)
    case "setThemePreference":
      if let preference = arguments?["preference"] as? String {
        defaults?.set(preference, forKey: themePreferenceKey)
      }
      saveWidgetPayload(arguments?["payload"], defaults: defaults)
      reloadWidgets()
      result(nil)
    case "setWidgetDisplaySettings":
      if let mode = arguments?["mode"] as? String {
        defaults?.set(mode, forKey: widgetModeKey)
      }
      if let date = arguments?["date"] as? String {
        defaults?.set(date, forKey: widgetFixedDateKey)
      }
      if let time = arguments?["time"] as? String {
        defaults?.set(time, forKey: widgetFixedTimeKey)
      }
      saveWidgetPayload(arguments?["payload"], defaults: defaults)
      reloadWidgets()
      result(nil)
    case "scheduleClassReminders":
      result(nil)
    case "showClassReminderTest":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveWidgetPayload(_ payload: Any?, defaults: UserDefaults?) {
    guard
      let defaults,
      let payload = payload,
      JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(withJSONObject: payload),
      let text = String(data: data, encoding: .utf8)
    else {
      return
    }
    defaults.set(text, forKey: widgetPayloadKey)
  }

  private func reloadWidgets() {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
