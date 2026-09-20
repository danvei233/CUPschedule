import 'package:flutter/material.dart';

/// Keep device, backend and model-service settings in clearly scoped sections.
class RecordingSettingsLayout extends StatelessWidget {
  const RecordingSettingsLayout({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.summaries,
    required this.children,
    required this.busy,
    required this.onRefresh,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final List<String> summaries;
  final List<Widget> children;
  final bool busy;
  final VoidCallback onRefresh;

  static const titles = ['连接与同步', '自动录音', '音频转写', '笔记 AI', '提示词', '任务管理'];
  static const descriptions = [
    '本机设置 · 连接 Go 后端，管理课表同步与录音上传。',
    '本机设置 · 管理 root、后台守护与按课表录音。',
    '服务端设置 · 连接 Python 音频服务，管理转写模型与推理并发。',
    '服务端设置 · 配置生成笔记使用的 AI 接口、模型与并发。',
    '服务端设置 · 分别设置转写术语与笔记整理要求。',
    '服务端任务 · 查看处理状态，停止、继续或重试任务。',
  ];
  static const icons = [
    Icons.link,
    Icons.alarm,
    Icons.graphic_eq,
    Icons.auto_awesome,
    Icons.edit_note,
    Icons.playlist_play,
  ];
  static const colors = [
    Colors.blue,
    Colors.teal,
    Colors.deepPurple,
    Colors.orange,
    Colors.cyan,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    Widget symbol(int i) => Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colors[i].withValues(alpha: .16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icons[i],
        color: dark ? colors[i].shade200 : colors[i].shade700,
        size: 22,
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final content = ListView(
              key: PageStorageKey('recording-settings-$selected'),
              padding: EdgeInsets.fromLTRB(wide ? 20 : 12, 8, 12, 28),
              children: [
                Row(
                  children: [
                    symbol(selected),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        titles[selected],
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(descriptions[selected], style: theme.textTheme.bodyMedium),
                const SizedBox(height: 18),
                Card(
                  margin: EdgeInsets.zero,
                  color: scheme.surface.withValues(alpha: .94),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    child: AbsorbPointer(
                      absorbing: busy,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                  ),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '课堂记录设置',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新服务端配置与任务',
                        onPressed: busy ? null : onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 3,
                  child: busy ? const LinearProgressIndicator() : null,
                ),
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < titles.length; i++)
                          ChoiceChip(
                            avatar: Icon(icons[i], size: 18),
                            label: Text(titles[i]),
                            selected: selected == i,
                            showCheckmark: false,
                            onSelected: (_) => onSelected(i),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 270,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  0,
                                  24,
                                ),
                                children: [
                                  for (var i = 0; i < titles.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Material(
                                        color: selected == i
                                            ? scheme.primaryContainer
                                            : scheme.surface.withValues(
                                                alpha: .85,
                                              ),
                                        borderRadius: BorderRadius.circular(16),
                                        child: ListTile(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          leading: symbol(i),
                                          title: Text(
                                            titles[i],
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: selected == i
                                                  ? scheme.onPrimaryContainer
                                                  : scheme.onSurface,
                                            ),
                                          ),
                                          subtitle: Text(
                                            summaries[i],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: selected == i
                                                  ? scheme.onPrimaryContainer
                                                  : scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          onTap: () => onSelected(i),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
