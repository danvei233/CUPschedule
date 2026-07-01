package cn.blackbook.blackbook.widget

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import cn.blackbook.blackbook.R
import java.time.LocalDate
import java.time.LocalTime
import kotlin.math.roundToInt

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

    override fun getCount(): Int = if (courses.isEmpty()) 0 else courses.size + 1

    override fun getViewAt(position: Int): RemoteViews {
        val course = courses.getOrNull(position)
        if (course == null) {
            val views = RemoteViews(context.packageName, R.layout.widget_today_click_spacer)
            val fillInIntent = Intent().apply {
                action = "cn.blackbook.blackbook.action.OPEN_WIDGET"
                data = Uri.parse("blackbook://widget/open")
            }
            views.setOnClickFillInIntent(R.id.widget_click_spacer_root, fillInIntent)
            return views
        }
        val theme = WidgetTheme.colors(context)
        val views = RemoteViews(context.packageName, R.layout.widget_today_class_item)
        val colorAccent = course.colorAccent()
        val iconAccent = course.iconAccent()
        views.setInt(
            R.id.widget_course_item_root,
            "setBackgroundResource",
            theme.cardResource,
        )
        views.setImageViewBitmap(
            R.id.course_icon,
            MaterialIconBitmapFactory.render(
                context = context,
                codePoint = iconAccent.iconCodePoint,
                color = colorAccent.color,
            ),
        )
        views.setTextColor(R.id.course_name, theme.foreground)
        views.setTextColor(R.id.course_place, theme.muted)
        views.setInt(R.id.course_accent_bar, "setBackgroundColor", colorAccent.color)
        views.setTextViewText(R.id.course_name, course.name)
        views.setTextViewText(R.id.course_place, course.compactSubtitle)
        val fillInIntent = Intent().apply {
            action = "cn.blackbook.blackbook.action.OPEN_WIDGET_COURSE"
            data = Uri.parse("blackbook://widget/course/$position")
            putExtra("course_name", course.name)
            putExtra("course_subtitle", course.compactSubtitle)
        }
        views.setOnClickFillInIntent(R.id.widget_course_item_root, fillInIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}

private data class CourseAccent(
    val key: String,
    val color: Int,
    val iconCodePoint: Int,
) {
    companion object {
        val fallback = CourseAccent(
            "general",
            Color.rgb(89, 103, 123),
            0xf33c,
        )
    }
}

private val courseAccents = listOf(
    CourseAccent("computer", Color.rgb(22, 117, 183), 0xefb2),
    CourseAccent("ai_data", Color.rgb(17, 153, 130), 0xf382),
    CourseAccent("math", Color.rgb(115, 88, 200), 0xf0ba),
    CourseAccent("physics", Color.rgb(28, 126, 178), 0xeedd),
    CourseAccent("chemistry", Color.rgb(200, 117, 22), 0xf33d),
    CourseAccent("experiment", Color.rgb(212, 85, 69), 0xf33d),
    CourseAccent("practice", Color.rgb(67, 122, 194), 0xef78),
    CourseAccent("geology", Color.rgb(33, 131, 87), 0xf42b),
    CourseAccent("engineering", Color.rgb(104, 86, 199), 0xee7a),
    CourseAccent("mechanical", Color.rgb(198, 93, 51), 0xf2c7),
    CourseAccent("materials", Color.rgb(185, 133, 23), 0xef37),
    CourseAccent("environment", Color.rgb(61, 140, 67), 0xf005),
    CourseAccent("economy", Color.rgb(196, 102, 53), 0xee32),
    CourseAccent("law", Color.rgb(82, 107, 192), 0xf0c0),
    CourseAccent("language", Color.rgb(89, 100, 200), 0xf45e),
    CourseAccent("sports", Color.rgb(23, 126, 168), 0xf3c8),
    CourseAccent("thinking", Color.rgb(36, 127, 88), 0xf08b1),
    CourseAccent("design", Color.rgb(201, 77, 131), 0xf05ed),
    CourseAccent("article", Color.rgb(184, 119, 25), 0xee93),
    CourseAccent.fallback,
)

private val strongAccentRules = listOf(
    "chemistry" to listOf(
        "化工原理",
        "化工热力学",
        "化工传递",
        "传递过程",
        "化学反应工程",
        "分离工程",
        "化工设计",
        "化工安全",
        "化工导论",
        "化工过程",
        "化工设备",
        "化学工程",
        "石油加工",
        "石油炼制",
        "催化",
        "反应器",
        "有机化学",
        "无机化学",
        "分析化学",
        "物理化学",
        "普通化学",
        "化学原理",
        "化学",
    ),
    "math" to listOf(
        "概率论",
        "概率统计",
        "数理统计",
        "统计学",
        "高等数学",
        "线性代数",
        "离散数学",
        "数学建模",
        "复变函数",
        "积分变换",
        "微积分",
        "矩阵理论",
        "数学分析",
        "数学物理方法",
        "数理方程",
        "最优化方法",
        "矢量分析",
        "计算方法",
        "数值计算",
        "数值分析",
        "运筹学",
    ),
    "experiment" to listOf("实验", "监测实验", "物理化学实验", "大学物理实验", "分析测试", "测定", "测量"),
    "physics" to listOf("大学物理", "物理化学实验", "物理化学", "物理", "力学", "电磁", "光学", "热学", "量子"),
    "computer" to listOf("计算机", "程序设计", "软件", "网络", "数据库", "操作系统", "数据结构", "c语言", "matlab", "python", "java", "web", "信息系统"),
    "ai_data" to listOf("机器学习", "人工智能", "深度学习", "统计学习", "数据挖掘", "大数据", "数据分析", "数据科学", "算法设计"),
    "mechanical" to listOf("机械制图", "工程图学", "机械", "机电", "电工", "电子", "自动化", "控制", "机器人"),
    "environment" to listOf("环境", "生态", "污染", "碳中和", "碳封存", "环保", "土壤学", "微生物学"),
    "geology" to listOf("地质", "油气", "矿物", "岩石", "沉积", "测井", "勘探", "地震", "构造", "地球物理", "地理信息", "遥感"),
    "materials" to listOf("材料", "新能源", "储能", "高分子", "金属", "腐蚀", "焊接"),
    "thinking" to listOf("思政", "毛泽东", "马克思", "习近平", "中国近现代史", "思想道德", "形势与政策"),
    "sports" to listOf("体育", "篮球", "足球", "排球", "武术", "健美操", "运动"),
    "language" to listOf("大学英语", "学术英语", "专业英语", "英语", "俄语", "日语", "外语", "翻译", "口语", "听力"),
    "article" to listOf("毕业论文", "毕业设计", "论文"),
    "practice" to listOf("实习", "实训", "实践", "课程设计", "大作业", "创新创业", "训练"),
    "economy" to listOf("经济", "管理", "会计", "财务", "营销", "项目管理", "金融"),
    "law" to listOf("法律", "法学", "知识产权", "法规"),
    "design" to listOf("设计", "写作", "检索", "绘图"),
    "engineering" to listOf("安全工程", "海洋工程", "储运工程", "建筑", "设备"),
)

private val weakAccentRules = listOf(
    "chemistry" to listOf("化工", "化学", "炼制"),
    "math" to listOf("数学", "统计"),
    "computer" to listOf("程序", "编程", "信息"),
    "engineering" to listOf("工程", "工艺", "设备"),
)

private fun WidgetCourse.colorAccent(): CourseAccent {
    val explicit = colorKey?.let(::courseAccentForKey)
    if (explicit != null) {
        return explicit
    }
    return automaticAccent()
}

private fun WidgetCourse.iconAccent(): CourseAccent {
    val explicit = iconKey?.let(::courseAccentForKey)
    if (explicit != null) {
        return explicit
    }
    return automaticAccent()
}

private fun WidgetCourse.automaticAccent(): CourseAccent {
    val text = normalizeAccentText(name)
    for ((key, keywords) in strongAccentRules) {
        if (keywords.any { text.contains(normalizeAccentText(it)) }) {
            return courseAccentForKey(key) ?: CourseAccent.fallback
        }
    }
    val fullText = normalizeAccentText(
        listOf(name, lessonCode, courseCode)
            .filter { it.trim().isNotEmpty() }
            .joinToString(" "),
    )
    for ((key, keywords) in weakAccentRules) {
        if (keywords.any { fullText.contains(normalizeAccentText(it)) }) {
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

private object MaterialIconBitmapFactory {
    private val assetPaths = listOf(
        "flutter_assets/fonts/MaterialIcons-Regular.otf",
        "fonts/MaterialIcons-Regular.otf",
    )
    private val iconCache = mutableMapOf<String, Bitmap>()
    private var cachedTypeface: Typeface? = null
    private var didTryLoad = false

    fun render(context: android.content.Context, codePoint: Int, color: Int): Bitmap {
        val density = context.resources.displayMetrics.density
        val size = (18f * density).roundToInt().coerceAtLeast(18)
        val cacheKey = "$codePoint:$color:$size"
        iconCache[cacheKey]?.let { return it }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textAlign = Paint.Align.CENTER
            textSize = size * 0.92f
            typeface = materialTypeface(context) ?: Typeface.DEFAULT
        }
        val text = String(Character.toChars(codePoint))
        val metrics = paint.fontMetrics
        val baseline = size / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(text, size / 2f, baseline, paint)
        iconCache[cacheKey] = bitmap
        return bitmap
    }

    @Synchronized
    private fun materialTypeface(context: android.content.Context): Typeface? {
        if (didTryLoad) {
            return cachedTypeface
        }
        didTryLoad = true
        for (path in assetPaths) {
            val typeface = runCatching {
                Typeface.createFromAsset(context.assets, path)
            }.getOrNull()
            if (typeface != null) {
                cachedTypeface = typeface
                return typeface
            }
        }
        return null
    }
}
