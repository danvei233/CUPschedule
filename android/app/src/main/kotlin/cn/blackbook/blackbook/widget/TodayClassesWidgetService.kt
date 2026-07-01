package cn.blackbook.blackbook.widget

import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import cn.blackbook.blackbook.R
import java.time.LocalDate
import java.time.LocalTime

class TodayClassesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodayClassesRemoteViewsFactory(applicationContext)
    }
}

class TodayClassesRemoteViewsFactory(
    private val context: android.content.Context,
) : RemoteViewsService.RemoteViewsFactory {
    private var courses: List<WidgetCourse> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        courses = TodayClassesRepository.loadWidget(
            context = context,
            nowDate = LocalDate.now(),
            nowTime = LocalTime.now(),
        ).courses
    }

    override fun onDestroy() {
        courses = emptyList()
    }

    override fun getCount(): Int = courses.size

    override fun getViewAt(position: Int): RemoteViews {
        val course = courses.getOrNull(position)
        val theme = WidgetTheme.colors(context)
        val views = RemoteViews(context.packageName, R.layout.widget_today_class_item)
        val accent = course?.accent() ?: CourseAccent.fallback
        views.setInt(
            R.id.widget_course_item_root,
            "setBackgroundResource",
            theme.cardResource,
        )
        views.setTextColor(R.id.course_icon, accent.color)
        views.setTextColor(R.id.course_name, theme.foreground)
        views.setTextColor(R.id.course_place, theme.muted)
        views.setInt(R.id.course_accent_bar, "setBackgroundColor", accent.color)
        if (course != null) {
            views.setTextViewText(R.id.course_icon, course.iconText())
            views.setTextViewText(R.id.course_name, course.name)
            views.setTextViewText(R.id.course_place, course.compactSubtitle)
        }
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}

private data class CourseAccent(
    val key: String,
    val color: Int,
    val icon: String,
) {
    companion object {
        val fallback = CourseAccent("general", Color.rgb(89, 103, 123), "课")
    }
}

private val courseAccents = listOf(
    CourseAccent("computer", Color.rgb(22, 117, 183), "计"),
    CourseAccent("ai_data", Color.rgb(17, 153, 130), "数"),
    CourseAccent("math", Color.rgb(115, 88, 200), "函"),
    CourseAccent("physics", Color.rgb(28, 126, 178), "物"),
    CourseAccent("chemistry", Color.rgb(200, 117, 22), "化"),
    CourseAccent("experiment", Color.rgb(212, 85, 69), "实"),
    CourseAccent("practice", Color.rgb(67, 122, 194), "践"),
    CourseAccent("geology", Color.rgb(33, 131, 87), "油"),
    CourseAccent("engineering", Color.rgb(104, 86, 199), "工"),
    CourseAccent("mechanical", Color.rgb(198, 93, 51), "机"),
    CourseAccent("materials", Color.rgb(185, 133, 23), "材"),
    CourseAccent("environment", Color.rgb(61, 140, 67), "环"),
    CourseAccent("economy", Color.rgb(196, 102, 53), "经"),
    CourseAccent("law", Color.rgb(82, 107, 192), "法"),
    CourseAccent("language", Color.rgb(89, 100, 200), "英"),
    CourseAccent("sports", Color.rgb(23, 126, 168), "体"),
    CourseAccent("thinking", Color.rgb(36, 127, 88), "思"),
    CourseAccent("design", Color.rgb(201, 77, 131), "设"),
    CourseAccent("article", Color.rgb(184, 119, 25), "文"),
    CourseAccent.fallback,
)

private val strongAccentRules = listOf(
    "chemistry" to listOf("化工原理", "化工热力学", "化学反应工程", "分离工程", "化工", "化学", "炼制", "催化"),
    "math" to listOf("概率论", "概率统计", "数理统计", "高等数学", "线性代数", "数学", "统计", "运筹学"),
    "experiment" to listOf("实验", "分析测试", "测定", "测量"),
    "physics" to listOf("大学物理", "物理", "力学", "电磁", "光学"),
    "computer" to listOf("计算机", "程序设计", "软件", "网络", "数据库", "数据结构"),
    "ai_data" to listOf("机器学习", "人工智能", "数据挖掘", "大数据", "数据分析"),
    "mechanical" to listOf("机械制图", "工程图学", "机械", "机电", "自动化", "控制"),
    "environment" to listOf("环境", "生态", "污染", "环保"),
    "geology" to listOf("地质", "油气", "矿物", "测井", "勘探"),
    "materials" to listOf("材料", "新能源", "储能", "高分子"),
    "thinking" to listOf("思政", "毛泽东", "马克思", "习近平", "中国近现代史"),
    "sports" to listOf("体育", "篮球", "足球", "排球", "运动"),
    "language" to listOf("大学英语", "学术英语", "英语", "俄语", "日语", "外语"),
    "article" to listOf("毕业论文", "毕业设计", "论文"),
    "practice" to listOf("实习", "实训", "实践", "课程设计", "创新创业"),
    "economy" to listOf("经济", "管理", "会计", "财务", "营销", "金融"),
    "law" to listOf("法律", "法学", "知识产权", "法规"),
    "design" to listOf("设计", "写作", "检索", "绘图"),
    "engineering" to listOf("安全工程", "海洋工程", "储运工程", "建筑", "设备", "工程"),
)

private fun WidgetCourse.accent(): CourseAccent {
    val explicit = colorKey?.let(::courseAccentForKey)
    if (explicit != null) {
        return explicit
    }
    return automaticAccent()
}

private fun WidgetCourse.iconText(): String {
    val explicit = iconKey?.let(::courseAccentForKey)
    return (explicit ?: automaticAccent()).icon
}

private fun WidgetCourse.automaticAccent(): CourseAccent {
    val text = normalizeAccentText(name)
    for ((key, keywords) in strongAccentRules) {
        if (keywords.any { text.contains(normalizeAccentText(it)) }) {
            return courseAccentForKey(key) ?: CourseAccent.fallback
        }
    }
    return CourseAccent.fallback
}

private fun courseAccentForKey(key: String): CourseAccent? {
    val normalized = when (key) {
        "book" -> "general"
        "biology" -> "practice"
        "chart" -> "ai_data"
        "building" -> "engineering"
        "ecology" -> "environment"
        "workshop" -> "practice"
        "lab" -> "experiment"
        else -> key
    }
    return courseAccents.firstOrNull { it.key == normalized }
}

private fun normalizeAccentText(value: String): String {
    return value.lowercase()
        .replace(Regex("\\s+"), "")
        .replace('（', '(')
        .replace('）', ')')
}
