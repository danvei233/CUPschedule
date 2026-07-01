package cn.blackbook.blackbook

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import cn.blackbook.blackbook.widget.ClassReminderReceiver
import cn.blackbook.blackbook.widget.TodayClassesWidgetProvider
import cn.blackbook.blackbook.widget.WidgetTheme
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "blackbook/today_classes_widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    TodayClassesWidgetProvider.refreshAll(this)
                    result.success(null)
                }
                "scheduleClassReminders" -> {
                    ClassReminderReceiver.scheduleNext(this)
                    result.success(null)
                }
                "showClassReminderTest" -> {
                    val permissionState = ensureNotificationPermission {
                        result.success(showClassReminderTest())
                    }
                    if (permissionState == null) {
                        pendingNotificationResult = result
                    } else if (!permissionState) {
                        result.success(false)
                    }
                }
                "setThemePreference" -> {
                    val preference = call.argument<String>("preference") ?: "system"
                    getSharedPreferences(
                        WidgetTheme.nativePreferencesName,
                        Context.MODE_PRIVATE,
                    ).edit()
                        .putString(WidgetTheme.themePreferenceKey, preference)
                        .apply()
                    TodayClassesWidgetProvider.refreshAll(this)
                    result.success(null)
                }
                "setWidgetDisplaySettings" -> {
                    val preferences = getSharedPreferences(
                        WidgetTheme.nativePreferencesName,
                        Context.MODE_PRIVATE,
                    ).edit()
                    preferences.putString(
                        "widget.today.content_mode",
                        call.argument<String>("mode") ?: "live",
                    )
                    preferences.putString(
                        "widget.today.fixed_date",
                        call.argument<String>("date") ?: "",
                    )
                    preferences.putString(
                        "widget.today.fixed_time",
                        call.argument<String>("time") ?: "",
                    )
                    preferences.apply()
                    TodayClassesWidgetProvider.refreshAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequest) {
            return
        }
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val result = pendingNotificationResult
        pendingNotificationResult = null
        if (!granted) {
            openNotificationSettings()
        }
        result?.success(if (granted) showClassReminderTest() else false)
    }

    private fun ensureNotificationPermission(onGranted: () -> Unit): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            onGranted()
            return true
        }
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            onGranted()
            return true
        }
        if (shouldShowRequestPermissionRationale(permission)) {
            openNotificationSettings()
            return false
        }
        requestPermissions(arrayOf(permission), notificationPermissionRequest)
        return null
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        }
        startActivity(intent)
    }

    private fun showClassReminderTest(): Boolean {
        val shown = ClassReminderReceiver.showTest(this)
        if (!shown) {
            openNotificationSettings()
        }
        return shown
    }

    companion object {
        private const val notificationPermissionRequest = 3317
    }
}
