package cn.blackbook.blackbook.widget

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import cn.blackbook.blackbook.R

data class WidgetThemeColors(
    val background: Int,
    val backgroundResource: Int,
    val foreground: Int,
    val muted: Int,
    val card: Int,
    val cardResource: Int,
    val accent: Int,
)

object WidgetTheme {
    const val nativePreferencesName = "BlackbookWidgetPreferences"
    const val themePreferenceKey = "app.theme_mode"

    private const val preferencesName = "FlutterSharedPreferences"
    private const val keyPrefix = "flutter."

    fun colors(context: Context): WidgetThemeColors {
        val preference = themePreference(context)
        return when (preference) {
            "light" -> lightColors
            "dark" -> darkColors
            else -> if (isSystemDark(context)) darkColors else lightColors
        }
    }

    private fun themePreference(context: Context): String {
        val nativePreferences = context.getSharedPreferences(
            nativePreferencesName,
            Context.MODE_PRIVATE,
        )
        val nativeValue = nativePreferences.getString(themePreferenceKey, null)
        if (!nativeValue.isNullOrBlank()) {
            return nativeValue
        }
        val flutterPreferences = context.getSharedPreferences(
            preferencesName,
            Context.MODE_PRIVATE,
        )
        return flutterPreferences.getString(themePreferenceKey, null)
            ?: flutterPreferences.getString(prefKey(themePreferenceKey), "system")
            ?: "system"
    }

    private fun isSystemDark(context: Context): Boolean {
        val mask = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mask == Configuration.UI_MODE_NIGHT_YES
    }

    private fun prefKey(key: String): String = "$keyPrefix$key"

    private val lightColors = WidgetThemeColors(
        background = Color.rgb(248, 250, 255),
        backgroundResource = R.drawable.widget_background_light,
        foreground = Color.rgb(23, 26, 34),
        muted = Color.rgb(111, 116, 128),
        card = Color.WHITE,
        cardResource = R.drawable.widget_course_item_background_light,
        accent = Color.rgb(181, 30, 35),
    )

    private val darkColors = WidgetThemeColors(
        background = Color.rgb(16, 17, 22),
        backgroundResource = R.drawable.widget_background_dark,
        foreground = Color.rgb(242, 244, 250),
        muted = Color.rgb(180, 187, 203),
        card = Color.rgb(24, 27, 36),
        cardResource = R.drawable.widget_course_item_background_dark,
        accent = Color.rgb(255, 122, 125),
    )
}
