package cn.blackbook.blackbook.widget

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ObjectInputStream
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.min

data class WidgetSemester(
    val id: Int,
    val name: String,
    val startDate: LocalDate,
    val endDate: LocalDate,
    val weekStartOnSunday: Boolean,
) {
    val totalWeeks: Int
        get() = ceil(ChronoUnit.DAYS.between(startDate, endDate).toDouble() / 7.0).toInt()
            .coerceAtLeast(1)

    fun weekIndexFor(date: LocalDate): Int {
        if (date.isBefore(startDate)) return 1
        val week = (ChronoUnit.DAYS.between(startDate, date) / 7 + 1).toInt()
        return week.coerceIn(1, totalWeeks)
    }

    fun weekdayFor(date: LocalDate): Int {
        return date.dayOfWeek.value
    }
}

data class WidgetCourse(
    val lessonId: Int,
    val lessonCode: String,
    val courseCode: String,
    val name: String,
    val room: String,
    val building: String,
    val weeksText: String,
    val teachers: List<String>,
    val weekday: Int,
    val weekIndexes: Set<Int>,
    val startTime: LocalTime,
    val endTime: LocalTime,
    val startUnit: Int,
    val endUnit: Int,
    val iconKey: String?,
    val colorKey: String?,
) {
    val timeText: String
        get() = "${timeFormatter.format(startTime)}\n${timeFormatter.format(endTime)}"

    val compactTimeText: String
        get() = "${timeFormatter.format(startTime)}-${timeFormatter.format(endTime)}"

    val subtitle: String
        get() {
            val teacher = teachers.firstOrNull { it.isNotBlank() }.orEmpty()
            val parts = listOf(room, teacher).filter { it.isNotBlank() }
            return if (parts.isEmpty()) "地点未公布" else parts.joinToString("  ")
        }

    val compactSubtitle: String
        get() {
            val place = room.ifBlank { building }
            val parts = listOf(compactTimeText, place).filter { it.isNotBlank() }
            return parts.joinToString("  ")
        }

    fun teacherTextForKey(): String {
        return if (teachers.isEmpty()) {
            "教师未公布"
        } else {
            teachers.joinToString(" / ")
        }
    }

    companion object {
        private val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
    }
}

data class TodayWidgetData(
    val semesterName: String?,
    val weekIndex: Int?,
    val courses: List<WidgetCourse>,
    val referenceDate: LocalDate? = null,
    val referenceTime: LocalTime? = null,
    val fixedMode: Boolean = false,
)

data class ClassReminderData(
    val semesterName: String,
    val weekIndex: Int,
    val classDate: LocalDate,
    val course: WidgetCourse,
) {
    val classStart: LocalDateTime
        get() = LocalDateTime.of(classDate, course.startTime)

    val reminderAt: LocalDateTime
        get() = classStart.minusMinutes(5)
}

object TodayClassesRepository {
    private const val preferencesName = "FlutterSharedPreferences"
    private const val keyPrefix = "flutter."
    private const val listPrefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
    private const val jsonListPrefix = "$listPrefix!"
    private const val selectedSemesterIdKey = "cup.imported.selected_semester_id"
    private const val semesterIdsKey = "cup.imported.semester.ids"
    private const val semesterPrefix = "cup.imported.semester."
    private const val printDataPrefix = "cup.imported.print_data."
    private const val startDateOverridePrefix = "cup.imported.start_date_override."
    private const val conflictChoicePrefix = "cup.imported.conflict_choice."
    private const val widgetModeKey = "widget.today.content_mode"
    private const val widgetFixedDateKey = "widget.today.fixed_date"
    private const val widgetFixedTimeKey = "widget.today.fixed_time"
    private const val nativePreferencesName = "BlackbookWidgetPreferences"
    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

    fun loadWidget(context: Context, nowDate: LocalDate, nowTime: LocalTime): TodayWidgetData {
        val reference = widgetReferenceTime(context, nowDate, nowTime)
        return loadFor(
            context = context,
            targetDate = reference.date,
            referenceTime = reference.time,
            fixedMode = reference.fixed,
        )
    }

    fun loadToday(context: Context, nowDate: LocalDate, nowTime: LocalTime): TodayWidgetData {
        return loadFor(
            context = context,
            targetDate = nowDate,
            referenceTime = nowTime,
            fixedMode = false,
        )
    }

    fun nextClassReminder(
        context: Context,
        nowDate: LocalDate,
        nowTime: LocalTime,
        includeActiveWindow: Boolean = false,
    ): ClassReminderData? {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val schedules = storedSchedules(preferences)
        val now = LocalDateTime.of(nowDate, nowTime)
        val activeWindowStart = now.minusMinutes(6)
        var best: ClassReminderData? = null
        for (schedule in schedules) {
            val semester = schedule.semester
            for (dayOffset in 0..420) {
                val date = nowDate.plusDays(dayOffset.toLong())
                if (date.isBefore(semester.startDate)) {
                    continue
                }
                if (date.isAfter(semester.endDate)) {
                    break
                }
                val weekIndex = semester.weekIndexFor(date)
                val weekday = semester.weekdayFor(date)
                val courses = resolveConflicts(
                    courses = schedule.courses.filter { course ->
                        course.weekday == weekday &&
                            course.weekIndexes.contains(weekIndex)
                    },
                    choices = schedule.choices,
                    weekIndex = weekIndex,
                ).sortedWith(compareBy<WidgetCourse> { it.startTime }.thenBy { it.startUnit })
                for (course in courses) {
                    val reminder = ClassReminderData(
                        semesterName = semester.name,
                        weekIndex = weekIndex,
                        classDate = date,
                        course = course,
                    )
                    val relevant = if (includeActiveWindow) {
                        reminder.reminderAt.isAfter(activeWindowStart) &&
                            !reminder.reminderAt.isAfter(now) &&
                            reminder.classStart.isAfter(now)
                    } else {
                        reminder.reminderAt.isAfter(now)
                    }
                    if (!relevant) {
                        continue
                    }
                    if (best == null || reminder.classStart.isBefore(best.classStart)) {
                        best = reminder
                    }
                }
                if (best != null && date.isAfter(best.classDate.plusDays(1))) {
                    break
                }
            }
        }
        return best
    }

    private fun loadFor(
        context: Context,
        targetDate: LocalDate,
        referenceTime: LocalTime,
        fixedMode: Boolean,
    ): TodayWidgetData {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        for (schedule in storedSchedules(preferences)) {
            val semester = schedule.semester
            if (targetDate.isBefore(semester.startDate) || targetDate.isAfter(semester.endDate)) {
                continue
            }
            val weekIndex = semester.weekIndexFor(targetDate)
            val weekday = semester.weekdayFor(targetDate)
            val courses = resolveConflicts(
                courses = schedule.courses
                    .filter { course ->
                        course.weekday == weekday &&
                            course.weekIndexes.contains(weekIndex) &&
                            course.endTime.isAfter(referenceTime)
                    },
                choices = schedule.choices,
                weekIndex = weekIndex,
            )
                .sortedWith(compareBy<WidgetCourse> { it.startTime }.thenBy { it.startUnit })
            return TodayWidgetData(
                semesterName = semester.name,
                weekIndex = weekIndex,
                courses = courses,
                referenceDate = targetDate,
                referenceTime = referenceTime,
                fixedMode = fixedMode,
            )
        }

        return TodayWidgetData(
            semesterName = null,
            weekIndex = null,
            courses = emptyList(),
            referenceDate = targetDate,
            referenceTime = referenceTime,
            fixedMode = fixedMode,
        )
    }

    private data class StoredSchedule(
        val id: Int,
        val semester: WidgetSemester,
        val courses: List<WidgetCourse>,
        val choices: Map<String, String>,
    )

    private data class WidgetReferenceTime(
        val date: LocalDate,
        val time: LocalTime,
        val fixed: Boolean,
    )

    private fun storedSchedules(
        preferences: android.content.SharedPreferences,
    ): List<StoredSchedule> {
        val selectedId = readInt(preferences, prefKey(selectedSemesterIdKey))
        val ids = readStringList(preferences, prefKey(semesterIdsKey))
        val candidateIds = buildList {
            if (selectedId != null) add(selectedId.toString())
            addAll(ids)
        }.distinct()
        return buildList {
            for (rawId in candidateIds) {
                val id = rawId.toIntOrNull() ?: continue
                val semesterText = preferences.getString(prefKey("$semesterPrefix$id"), null)
                    ?: continue
                val printDataText = preferences.getString(prefKey("$printDataPrefix$id"), null)
                    ?: continue
                val semester = parseSemester(
                    semesterText,
                    preferences.getString(prefKey("$startDateOverridePrefix$id"), null),
                ) ?: continue
                add(
                    StoredSchedule(
                        id = id,
                        semester = semester,
                        courses = parseCourses(printDataText),
                        choices = readConflictChoices(preferences, id),
                    ),
                )
            }
        }
    }

    private fun widgetReferenceTime(
        context: Context,
        nowDate: LocalDate,
        nowTime: LocalTime,
    ): WidgetReferenceTime {
        val nativePreferences = context.getSharedPreferences(
            nativePreferencesName,
            Context.MODE_PRIVATE,
        )
        val flutterPreferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val mode = readStringPreference(nativePreferences, widgetModeKey)
            ?: readStringPreference(flutterPreferences, widgetModeKey)
            ?: "live"
        if (mode != "fixed") {
            return WidgetReferenceTime(nowDate, nowTime, fixed = false)
        }
        val dateText = readStringPreference(nativePreferences, widgetFixedDateKey)
            ?: readStringPreference(flutterPreferences, widgetFixedDateKey)
        val timeText = readStringPreference(nativePreferences, widgetFixedTimeKey)
            ?: readStringPreference(flutterPreferences, widgetFixedTimeKey)
        val date = dateText
            ?.let { runCatching { LocalDate.parse(it, dateFormatter) }.getOrNull() }
            ?: nowDate
        val time = timeText
            ?.let { runCatching { LocalTime.parse(it.padStart(5, '0')) }.getOrNull() }
            ?: nowTime
        return WidgetReferenceTime(date, time, fixed = true)
    }

    private fun prefKey(key: String): String = "$keyPrefix$key"

    private fun readStringPreference(
        preferences: android.content.SharedPreferences,
        key: String,
    ): String? {
        val native = preferences.getString(key, null)
        if (!native.isNullOrBlank()) {
            return native
        }
        val flutter = preferences.getString(prefKey(key), null)
        if (!flutter.isNullOrBlank()) {
            return flutter
        }
        return null
    }

    private fun readInt(
        preferences: android.content.SharedPreferences,
        key: String,
    ): Int? {
        return when (val raw = preferences.all[key]) {
            is Int -> raw
            is Long -> raw.toInt()
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull()
            else -> null
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun readStringList(
        preferences: android.content.SharedPreferences,
        key: String,
    ): List<String> {
        val raw = preferences.all[key] ?: return emptyList()
        if (raw is Set<*>) {
            return raw.filterIsInstance<String>()
        }
        if (raw is String) {
            val text = when {
                raw.startsWith(jsonListPrefix) -> raw.removePrefix(jsonListPrefix)
                raw.startsWith(listPrefix) -> return decodeLegacyStringList(
                    raw.removePrefix(listPrefix),
                )
                else -> raw
            }
            return decodeJsonStringList(text)
        }
        return emptyList()
    }

    private fun decodeJsonStringList(text: String): List<String> {
        return runCatching {
            val json = JSONArray(text)
            List(json.length()) { index -> json.optString(index) }
        }.getOrDefault(emptyList())
    }

    private fun decodeLegacyStringList(encoded: String): List<String> {
        return runCatching {
            val bytes = Base64.decode(encoded, Base64.DEFAULT)
            ObjectInputStream(ByteArrayInputStream(bytes)).use { stream ->
                @Suppress("UNCHECKED_CAST")
                (stream.readObject() as? List<String>) ?: emptyList()
            }
        }.getOrDefault(emptyList())
    }

    private fun parseSemester(text: String, startDateOverride: String?): WidgetSemester? {
        return runCatching {
            val json = JSONObject(text)
            val startDate = startDateOverride
                ?.takeIf { it.isNotBlank() }
                ?.let { runCatching { LocalDate.parse(it, dateFormatter) }.getOrNull() }
                ?: LocalDate.parse(json.getString("startDate"), dateFormatter)
            WidgetSemester(
                id = json.getInt("id"),
                name = json.optString("nameZh", json.optString("name", "")),
                startDate = startDate,
                endDate = LocalDate.parse(json.getString("endDate"), dateFormatter),
                weekStartOnSunday = json.optBoolean("weekStartOnSunday", false),
            )
        }.getOrNull()
    }

    private fun parseCourses(text: String): List<WidgetCourse> {
        return runCatching {
            val root = JSONObject(text)
            val tables = root.optJSONArray("studentTableVms") ?: return emptyList()
            val table = tables.optJSONObject(0) ?: return emptyList()
            val activities = table.optJSONArray("activities") ?: return emptyList()
            buildList {
                for (index in 0 until activities.length()) {
                    val item = activities.optJSONObject(index) ?: continue
                    val course = parseCourse(item) ?: continue
                    add(course)
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun parseCourse(json: JSONObject): WidgetCourse? {
        val startTime = parseClock(json.optString("startTime")) ?: return null
        val endTime = parseClock(json.optString("endTime")) ?: return null
        val weekIndexes = json.optJSONArray("weekIndexes") ?: JSONArray()
        return WidgetCourse(
            lessonId = json.optInt("lessonId", 0),
            lessonCode = json.optString("lessonCode", ""),
            courseCode = json.optString("courseCode", ""),
            name = json.optString("courseName", "未命名课程"),
            room = json.optString("room", ""),
            building = json.optString("building", ""),
            weeksText = json.optString("weeksStr", ""),
            teachers = teachers(json.optJSONArray("teachers")),
            weekday = json.optInt("weekday", -1),
            weekIndexes = buildSet {
                for (index in 0 until weekIndexes.length()) {
                    add(weekIndexes.optInt(index))
                }
            },
            startTime = startTime,
            endTime = endTime,
            startUnit = json.optInt("startUnit", 0),
            endUnit = json.optInt("endUnit", 0),
            iconKey = json.optString("iconKey", "").takeIf { it.isNotBlank() },
            colorKey = json.optString("colorKey", "").takeIf { it.isNotBlank() },
        )
    }

    private fun resolveConflicts(
        courses: List<WidgetCourse>,
        choices: Map<String, String>,
        weekIndex: Int,
    ): List<WidgetCourse> {
        if (courses.size <= 1) {
            return courses
        }
        val groups = mutableListOf<List<WidgetCourse>>()
        var current = mutableListOf<WidgetCourse>()
        var currentWeekday = -1
        var currentStart = -1
        var currentEnd = -1
        for (course in courses.sortedWith(compareBy<WidgetCourse> { it.weekday }
            .thenBy { it.startUnit }
            .thenBy { it.endUnit }
            .thenBy { it.name })) {
            val overlaps = course.weekday == currentWeekday &&
                course.startUnit <= currentEnd &&
                currentStart <= course.endUnit
            if (current.isNotEmpty() && !overlaps) {
                groups.add(current)
                current = mutableListOf()
            }
            if (current.isEmpty()) {
                currentWeekday = course.weekday
                currentStart = course.startUnit
                currentEnd = course.endUnit
            } else {
                currentStart = minOf(currentStart, course.startUnit)
                currentEnd = maxOf(currentEnd, course.endUnit)
            }
            current.add(course)
        }
        if (current.isNotEmpty()) {
            groups.add(current)
        }
        return groups.map { group ->
            if (group.size == 1) {
                group.first()
            } else {
                selectedCourse(group, choices, weekIndex)
            }
        }
    }

    private fun selectedCourse(
        group: List<WidgetCourse>,
        choices: Map<String, String>,
        weekIndex: Int,
    ): WidgetCourse {
        val sorted = group.sortedWith(
            compareByDescending<WidgetCourse> { usefulnessScore(it) }
                .thenBy { it.startUnit }
                .thenBy { it.name },
        )
        val savedChoice = choices["$weekIndex.${conflictGroupKey(sorted)}"]
        if (savedChoice != null) {
            sorted.firstOrNull { activityChoiceKey(it) == savedChoice }?.let { return it }
        }
        return sorted.first()
    }

    private fun readConflictChoices(
        preferences: android.content.SharedPreferences,
        semesterId: Int,
    ): Map<String, String> {
        val prefix = prefKey("$conflictChoicePrefix$semesterId.")
        val result = mutableMapOf<String, String>()
        for ((key, value) in preferences.all) {
            if (!key.startsWith(prefix) || value !is String || value.isBlank()) {
                continue
            }
            result[key.substring(prefix.length)] = value
        }
        return result
    }

    private fun usefulnessScore(course: WidgetCourse): Int {
        var score = 0
        if (
            course.room.trim().isNotEmpty() &&
            !course.room.contains("咨询") &&
            !course.room.contains("具体")
        ) {
            score += 30
        }
        if (course.building.trim().isNotEmpty()) {
            score += 20
        }
        if (course.teachers.isNotEmpty()) {
            score += 10
        }
        if (course.weeksText.trim().isNotEmpty()) {
            score += 4
        }
        score += min(course.weekIndexes.size, 18)
        if (course.name.contains("非本周")) {
            score -= 40
        }
        return score
    }

    private fun conflictGroupKey(group: List<WidgetCourse>): String {
        return group.map { activityChoiceKey(it) }.sorted().joinToString("|")
    }

    private fun activityChoiceKey(course: WidgetCourse): String {
        return listOf(
            course.lessonId.toString(),
            course.lessonCode,
            course.courseCode,
            course.weekday.toString(),
            course.startUnit.toString(),
            course.endUnit.toString(),
            course.room,
            course.teacherTextForKey(),
        ).joinToString("#")
    }

    private fun teachers(values: JSONArray?): List<String> {
        if (values == null || values.length() == 0) return emptyList()
        return buildList {
            for (index in 0 until values.length()) {
                val value = values.optString(index, "").trim()
                if (value.isNotEmpty()) {
                    add(value)
                }
            }
        }
    }

    private fun parseClock(value: String): LocalTime? {
        return runCatching {
            LocalTime.parse(value.padStart(5, '0'))
        }.getOrNull()
    }
}
