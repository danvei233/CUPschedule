import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_theme_controller.dart';

class AppBackgroundLayer extends StatelessWidget {
  const AppBackgroundLayer({
    super.key,
    required this.settings,
    required this.imageBytes,
    required this.baseColor,
  });

  final AppBackgroundSettings settings;
  final Uint8List? imageBytes;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    return ColoredBox(
      color: baseColor,
      child: bytes == null
          ? const SizedBox.expand()
          : Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: settings.imageOpacity,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                ColoredBox(
                  color: settings.maskColor.withValues(
                    alpha: settings.maskOpacity,
                  ),
                ),
              ],
            ),
    );
  }
}

Color appPageBackgroundColor(BuildContext context, Color fallback) {
  return appHasVisibleBackground(context) ? Colors.transparent : fallback;
}

bool appHasVisibleBackground(BuildContext context) {
  final controller = AppThemeScope.maybeOf(context);
  return controller?.hasBackgroundImage == true &&
      Theme.of(context).brightness == Brightness.dark;
}
