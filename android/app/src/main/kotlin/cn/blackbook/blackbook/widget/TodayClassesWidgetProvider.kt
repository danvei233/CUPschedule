package cn.blackbook.blackbook.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import cn.blackbook.blackbook.MainActivity
import cn.blackbook.blackbook.R
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class TodayClassesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    override fun onEnabled(context: Context) {
        scheduleNextRefresh(context)
        ClassReminderReceiver.scheduleNext(context)
    }

    override fun onDisabled(context: Context) {
        cancelRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (
            intent.action == Intent.ACTION_TIME_CHANGED ||
            intent.action == Intent.ACTION_TIMEZONE_CHANGED ||
            intent.action == Intent.ACTION_DATE_CHANGED ||
            intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            refreshAll(context)
            ClassReminderReceiver.scheduleNext(context)
        }
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, TodayClassesWidgetProvider::class.java),
            )
            updateWidgets(context, manager, ids)
        }

        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val todayData = TodayClassesRepository.loadWidget(
                context = context,
                nowDate = LocalDate.now(),
                nowTime = LocalTime.now(),
            )
            for (appWidgetId in appWidgetIds) {
                val theme = WidgetTheme.colors(context)
                val views = RemoteViews(context.packageName, R.layout.widget_today_classes)
                val serviceIntent = Intent(context, TodayClassesWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    this.data = android.net.Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
                views.setRemoteAdapter(R.id.widget_course_list, serviceIntent)
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundResource",
                    theme.backgroundResource,
                )
                views.setTextColor(R.id.widget_title, theme.foreground)
                views.setTextColor(R.id.widget_time, theme.muted)
                views.setTextColor(R.id.widget_subtitle, theme.muted)
                views.setTextColor(R.id.widget_empty, theme.muted)
                views.setTextViewText(R.id.widget_time, LocalTime.now().format(timeFormatter))
                views.setTextViewText(
                    R.id.widget_subtitle,
                    subtitle(todayData),
                )
                views.setEmptyView(R.id.widget_course_list, R.id.widget_empty)
                views.setViewVisibility(
                    R.id.widget_empty,
                    if (todayData.courses.isEmpty()) {
                        android.view.View.VISIBLE
                    } else {
                        android.view.View.GONE
                    },
                )

                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    action = openWidgetAction
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag,
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                val itemPendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId + 2000,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag,
                )
                views.setPendingIntentTemplate(R.id.widget_course_list, itemPendingIntent)

                appWidgetManager.notifyAppWidgetViewDataChanged(
                    appWidgetId,
                    R.id.widget_course_list,
                )
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
            scheduleNextRefresh(context)
            ClassReminderReceiver.scheduleNext(context)
        }

        private fun subtitle(data: TodayWidgetData): String {
            val week = data.weekIndex?.let { "第${it}周" } ?: "未选择课表"
            val semester = data.semesterName?.takeIf { it.isNotBlank() }
            val count = data.courses.size
            val mode = if (data.fixedMode) {
                val date = data.referenceDate?.let { "${it.monthValue}/${it.dayOfMonth}" }
                val time = data.referenceTime?.format(timeFormatter)
                listOfNotNull(date, time).joinToString(" ")
            } else {
                "剩余${count}节"
            }
            return listOfNotNull(semester, week, mode).joinToString("  ")
        }

        private fun scheduleNextRefresh(context: Context) {
            val data = TodayClassesRepository.loadWidget(
                context = context,
                nowDate = LocalDate.now(),
                nowTime = LocalTime.now(),
            )
            val next = if (data.fixedMode) {
                LocalDate.now().plusDays(1).atStartOfDay().plusSeconds(1)
            } else {
                val nextCourseEnd = data.courses.minOfOrNull { it.endTime }
                if (nextCourseEnd != null) {
                    LocalDateTime.of(LocalDate.now(), nextCourseEnd).plusSeconds(1)
                } else {
                    LocalDate.now().plusDays(1).atStartOfDay().plusSeconds(1)
                }
            }
            val triggerAt = next.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = refreshPendingIntent(context)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        }

        private fun cancelRefresh(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(refreshPendingIntent(context))
        }

        private fun refreshPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, TodayClassesWidgetRefreshReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                1001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag,
            )
        }

        private val immutableFlag: Int
            get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }

        private val mutableFlag: Int
            get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }

        private const val openWidgetAction = "cn.blackbook.blackbook.action.OPEN_WIDGET"

        private val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
    }
}
