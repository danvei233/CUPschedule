import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_palette.dart';
import 'app_theme_controller.dart';

class AppBackgroundSettingsPage extends StatefulWidget {
  const AppBackgroundSettingsPage({super.key, required this.controller});

  final AppThemeController controller;

  @override
  State<AppBackgroundSettingsPage> createState() =>
      _AppBackgroundSettingsPageState();
}

class _AppBackgroundSettingsPageState extends State<AppBackgroundSettingsPage> {
  var _busy = false;

  static const _imageTypes = XTypeGroup(
    label: '图片',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    mimeTypes: [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/bmp',
    ],
    uniformTypeIdentifiers: ['public.image'],
  );

  static const _maskColors = [
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF202124),
    Color(0xFFB51E23),
    Color(0xFF245B4A),
    Color(0xFF425A78),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final palette = blackbookPalette(context);
        final settings = widget.controller.background;
        final enabled = widget.controller.hasBackgroundImage;
        return Scaffold(
          backgroundColor: appPageBackgroundColor(
            context,
            palette.pageBackground,
          ),
          body: SafeArea(
            child: Column(
              children: [
                _BackgroundHeader(onBack: () => Navigator.of(context).pop()),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AppBackgroundLayer(
                                settings: settings,
                                imageBytes:
                                    widget.controller.backgroundImageBytes,
                                baseColor: palette.surfaceAlt,
                              ),
                              if (!enabled)
                                Center(
                                  child: Icon(
                                    Icons.wallpaper_outlined,
                                    size: 38,
                                    color: palette.muted,
                                  ),
                                ),
                              Positioned(
                                left: 12,
                                bottom: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: palette.sheet.withValues(
                                      alpha: 0.82,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      enabled ? '背景预览' : '未设置背景图片',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: palette.ink,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _pickImage,
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.image_outlined),
                              label: Text(enabled ? '更换图片' : '选择图片'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: enabled && !_busy ? _clearImage : null,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('清空'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _SettingsSectionLabel(
                        icon: Icons.opacity_outlined,
                        title: '图片透明度',
                        value: '${(settings.imageOpacity * 100).round()}%',
                      ),
                      Slider(
                        value: settings.imageOpacity,
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: enabled
                            ? widget.controller.previewBackgroundImageOpacity
                            : null,
                        onChangeEnd: enabled
                            ? widget.controller.setBackgroundImageOpacity
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _SettingsSectionLabel(
                        icon: Icons.view_agenda_outlined,
                        title: '课程卡片透明度',
                        value: '${(settings.courseCardOpacity * 100).round()}%',
                      ),
                      Slider(
                        value: settings.courseCardOpacity,
                        min: 0.2,
                        max: 0.95,
                        divisions: 15,
                        onChanged: enabled
                            ? widget
                                  .controller
                                  .previewBackgroundCourseCardOpacity
                            : null,
                        onChangeEnd: enabled
                            ? widget.controller.setBackgroundCourseCardOpacity
                            : null,
                      ),
                      const Divider(height: 28),
                      _SettingsSectionLabel(
                        icon: Icons.layers_outlined,
                        title: '遮罩颜色',
                        value: _hexColor(settings.maskColor),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (final color in _maskColors)
                            _ColorSwatchButton(
                              color: color,
                              selected:
                                  color.toARGB32() ==
                                  settings.maskColor.toARGB32(),
                              onTap: enabled
                                  ? () => widget.controller
                                        .setBackgroundMaskColor(color)
                                  : null,
                            ),
                          _CustomColorButton(
                            enabled: enabled,
                            onTap: () => _pickCustomColor(settings.maskColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SettingsSectionLabel(
                        icon: Icons.gradient_outlined,
                        title: '遮罩强度',
                        value: '${(settings.maskOpacity * 100).round()}%',
                      ),
                      Slider(
                        value: settings.maskOpacity,
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: enabled
                            ? widget.controller.previewBackgroundMaskOpacity
                            : null,
                        onChangeEnd: enabled
                            ? widget.controller.setBackgroundMaskOpacity
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final source = await openFile(acceptedTypeGroups: const [_imageTypes]);
    if (source == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.setBackgroundImage(source);
    } on Object catch (error) {
      if (mounted) {
        _showMessage(_cleanError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearImage() async {
    setState(() => _busy = true);
    try {
      await widget.controller.clearBackgroundImage();
    } on Object catch (error) {
      if (mounted) {
        _showMessage(_cleanError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickCustomColor(Color current) async {
    final controller = TextEditingController(text: _hexColor(current));
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义遮罩颜色'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 7,
          decoration: const InputDecoration(
            labelText: 'HEX 颜色',
            hintText: '#000000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) {
      return;
    }
    final color = _parseHexColor(value);
    if (color == null) {
      _showMessage('请输入 6 位 HEX 颜色');
      return;
    }
    await widget.controller.setBackgroundMaskColor(color);
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

class _BackgroundHeader extends StatelessWidget {
  const _BackgroundHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Text(
            '背景设置',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: palette.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: palette.subtle,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Tooltip(
      message: _hexColor(color),
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: onTap == null ? color.withValues(alpha: 0.28) : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.primary : palette.divider,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 18,
                  color: color.computeLuminance() > 0.55
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Tooltip(
      message: '自定义颜色',
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 26,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: palette.surfaceAlt.withValues(alpha: enabled ? 1 : 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: palette.divider),
          ),
          child: Icon(
            Icons.colorize_outlined,
            size: 18,
            color: enabled ? palette.ink : palette.muted,
          ),
        ),
      ),
    );
  }
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _parseHexColor(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(normalized, radix: 16));
}
