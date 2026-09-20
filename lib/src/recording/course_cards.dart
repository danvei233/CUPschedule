import 'package:flutter/material.dart';
import 'recording_controller.dart';

String recordingDate(dynamic raw) {
  final date = DateTime.tryParse('$raw')?.toLocal();
  if (date == null) return '日期未知';
  String two(int n) => '$n'.padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}  ${two(date.hour)}:${two(date.minute)}';
}

String courseDuration(num seconds) => seconds >= 3600
    ? '${(seconds / 3600).toStringAsFixed(1)} 小时'
    : '${(seconds / 60).round()} 分钟';

String recordingStateLabel(String? state) =>
    const {
  'recording': '录制 / 上传中',
  'processing': '等待转写 / 处理中',
      'queued': '等待处理',
      'complete': '已归档',
      'transcribed': '转写完成',
      'running': '处理中',
      'succeeded': '已完成',
      'failed': '处理失败',
      'stopped': '已停止',
      'stopping': '正在停止',
      'waiting_config': '等待配置',
    }[state] ??
    '已保存';

class CourseStyle {
  CourseStyle(Json course) {
    final id = '${course['id']}';
    final index =
        id.codeUnits.fold<int>(0, (n, c) => (n * 31 + c) % 997) % colors.length;
    color = colors[index];
    final name = '${course['name']}';
    icon = name.contains('数学') || name.contains('微积分')
        ? Icons.functions_rounded
        : name.contains('物理')
        ? Icons.bolt_rounded
        : name.contains('化')
        ? Icons.science_outlined
        : name.contains('英语') || name.contains('语言')
        ? Icons.translate_rounded
        : name.contains('计算') || name.contains('程序')
        ? Icons.code_rounded
        : name.contains('历史') || name.contains('思想')
        ? Icons.auto_stories_outlined
        : [
            Icons.menu_book_rounded,
            Icons.school_outlined,
            Icons.lightbulb_outline_rounded,
            Icons.architecture_rounded,
            Icons.biotech_rounded,
            Icons.public_rounded,
          ][index];
  }
  static const colors = [
    Color(0xff4575dc),
    Color(0xff168978),
    Color(0xff9a62cb),
    Color(0xffbb7526),
    Color(0xffce5d70),
    Color(0xff3888a0),
  ];
  late final Color color;
  late final IconData icon;
}

class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.row, required this.onTap});
  final Json row;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final course = Json.from(row['course'] as Map);
    final style = CourseStyle(course);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xff202938);
    final muted = dark ? const Color(0xffcbd4e3) : const Color(0xff596779);
    final accent = dark
        ? Color.lerp(style.color, Colors.white, .4)!
        : style.color;
    return Material(
      color: Color.lerp(
        dark ? const Color(0xff1b2330) : Colors.white,
        style.color,
        dark ? .19 : .10,
      ),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(style.icon, color: accent, size: 27),
                  ),
                  const Spacer(),
                  Icon(Icons.north_east_rounded, size: 20, color: accent),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                course['id'] == 'misc' ? '随手录音' : '${course['name']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${course['teachers'] ?? ''}'.isEmpty
                    ? '我的课程资料库'
                    : '${course['teachers']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const Spacer(),
              Divider(color: accent.withValues(alpha: .18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.mic_none_rounded, size: 17, color: accent),
                  const SizedBox(width: 5),
                  Text(
                    '${row['recording_count'] ?? 0} 节录音',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    courseDuration(row['duration_seconds'] as num? ?? 0),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CourseGrid extends StatelessWidget {
  const CourseGrid({super.key, required this.rows, required this.onOpen});
  final List<Json> rows;
  final ValueChanged<Json> onOpen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = (bounds.maxWidth / 290).floor().clamp(1, 4);
      final scale = MediaQuery.textScalerOf(context).scale(1);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
          mainAxisExtent: 252 + (scale - 1).clamp(0, 2) * 100,
        ),
        itemCount: rows.length,
        itemBuilder: (_, i) => CourseCard(
          row: rows[i],
          onTap: () => onOpen(Json.from(rows[i]['course'] as Map)),
        ),
      );
    },
  );
}

class CourseOverview extends StatelessWidget {
  const CourseOverview({
    super.key,
    required this.course,
    required this.count,
    required this.seconds,
  });
  final Json course;
  final int count;
  final num seconds;
  @override
  Widget build(BuildContext context) {
    final style = CourseStyle(course);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Color.lerp(style.color, Colors.white, dark ? .4 : 0)!;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            Color.lerp(
              dark ? const Color(0xff202735) : Colors.white,
              style.color,
              .24,
            )!,
            dark ? const Color(0xff202735) : Colors.white,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, size: 42, color: accent),
          const SizedBox(height: 16),
          Text(
            '${course['name']}',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: dark ? Colors.white : const Color(0xff202938),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${course['teachers'] ?? ''}'.isEmpty
                ? '每一次课堂，都值得留下'
                : '${course['teachers']}',
            style: TextStyle(
              color: dark ? Colors.white70 : const Color(0xff596779),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              Chip(
                avatar: Icon(Icons.mic_none, color: accent),
                label: Text('$count 节录音'),
              ),
              Chip(
                avatar: Icon(Icons.schedule, color: accent),
                label: Text(courseDuration(seconds)),
              ),
              Chip(
                avatar: Icon(Icons.auto_awesome, color: accent),
                label: Text(
                  course['auto_record'] == true && course['id'] != 'misc'
                      ? '课程自动录音已开启'
                      : '手动录音',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RecordingArchiveGrid extends StatelessWidget {
  const RecordingArchiveGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = (bounds.maxWidth / 420).floor().clamp(1, 3);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map(
              (child) => SizedBox(
                width: (bounds.maxWidth - (columns - 1) * 12) / columns,
                child: child,
              ),
            )
            .toList(),
      );
    },
  );
}
