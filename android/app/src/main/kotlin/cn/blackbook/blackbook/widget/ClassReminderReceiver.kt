package cn.blackbook.blackbook.widget

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import cn.blackbook.blackbook.MainActivity
import cn.blackbook.blackbook.R
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class ClassReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminder = TodayClassesRepository.nextClassReminder(
            context = context,
            nowDate = LocalDate.now(),
            nowTime = LocalTime.now(),
            includeActiveWindow = true,
        )
        if (reminder != null) {
            showReminder(context, reminder)
        }
        scheduleNext(context)
    }

    companion object {
        private const val channelId = "blackbook_class_reminder"
        private const val requestCode = 2201
        private const val notificationId = 2202
        private val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

        fun scheduleNext(context: Context) {
            val reminder = TodayClassesRepository.nextClassReminder(
                context = context,
                nowDate = LocalDate.now(),
                nowTime = LocalTime.now(),
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = pendingIntent(context)
            if (reminder == null) {
                alarmManager.cancel(pendingIntent)
                return
            }
            val now = LocalDateTime.now()
            val triggerAtDateTime = if (reminder.reminderAt.isAfter(now)) {
                reminder.reminderAt
            } else {
                now.plusSeconds(2)
            }
            val triggerAt = triggerAtDateTime
                .atZone(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            } else {
                alarmManager.set(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            }
        }

        fun showTest(context: Context): Boolean {
            val course = WidgetCourse(
                lessonId = -1,
                lessonCode = "TEST",
                courseCode = "TEST",
                name = "测试课程提醒",
                room = "三教 101",
                building = "三教",
                weeksText = "测试",
                teachers = listOf("系统测试"),
                weekday = LocalDate.now().dayOfWeek.value,
                weekIndexes = setOf(1),
                startTime = LocalTime.now().plusMinutes(5),
                endTime = LocalTime.now().plusMinutes(50),
                startUnit = 1,
                endUnit = 2,
                iconKey = "general",
                colorKey = "general",
            )
            return showReminder(
                context = context,
                reminder = ClassReminderData(
                    semesterName = "测试课表",
                    weekIndex = 1,
                    classDate = LocalDate.now(),
                    course = course,
                ),
            )
        }

        private fun showReminder(context: Context, reminder: ClassReminderData): Boolean {
            if (!notificationsAllowed(context)) {
                return false
            }
            ensureChannel(context)
            val launchIntent = Intent(context, MainActivity::class.java)
            val contentIntent = PendingIntent.getActivity(
                context,
                requestCode,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag,
            )
            val course = reminder.course
            val timeText = "${timeFormatter.format(course.startTime)} - " +
                timeFormatter.format(course.endTime)
            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("${course.name} 还有 5 分钟上课")
                .setContentText(
                    listOf(timeText, course.room)
                        .filter { it.isNotBlank() }
                        .joinToString("  "),
                )
                .setStyle(
                    NotificationCompat.BigTextStyle().bigText(
                        listOf(
                            "第${reminder.weekIndex}周",
                            timeText,
                            course.room,
                            course.teachers.firstOrNull().orEmpty(),
                        ).filter { it.isNotBlank() }.joinToString("  "),
                    ),
                )
                .setContentIntent(contentIntent)
                .setFullScreenIntent(contentIntent, true)
                .setAutoCancel(true)
                .setOngoing(true)
                .setOnlyAlertOnce(false)
                .setTimeoutAfter(10 * 60 * 1000L)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setCategory(NotificationCompat.CATEGORY_EVENT)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
            requestPromotedOngoingIfAvailable(builder)
            val notification = builder.build()
            NotificationManagerCompat.from(context).notify(notificationId, notification)
            return true
        }

        private fun requestPromotedOngoingIfAvailable(builder: NotificationCompat.Builder) {
            runCatching {
                val method = builder.javaClass.getMethod(
                    "setRequestPromotedOngoing",
                    java.lang.Boolean.TYPE,
                )
                method.invoke(builder, true)
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            val existing = manager.getNotificationChannel(channelId)
            if (existing != null) {
                return
            }
            val channel = NotificationChannel(
                channelId,
                "上课提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "上课前 5 分钟提醒"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }

        private fun notificationsAllowed(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = context.checkSelfPermission(
                    android.Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    return false
                }
            }
            return NotificationManagerCompat.from(context).areNotificationsEnabled()
        }

        private fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, ClassReminderReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                requestCode,
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
    }
}
