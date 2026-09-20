import 'package:flutter/material.dart';

import 'src/account/account_center_dialog.dart';
import 'src/account/account_store.dart';
import 'src/app_background.dart';
import 'src/app_theme_controller.dart';
import 'src/schedule/schedule_page.dart';

class BlackbookApp extends StatefulWidget {
  const BlackbookApp({super.key});

  @override
  State<BlackbookApp> createState() => _BlackbookAppState();
}

class _BlackbookAppState extends State<BlackbookApp> {
  late final AppThemeController _themeController;
  late Future<ManagedAccountState> _accountStateFuture;
  final _accountStore = const AccountStore();
  bool _preparingBackground = true;

  @override
  void initState() {
    super.initState();
    _themeController = AppThemeController();
    // Keep the native launch surface until the saved theme and wallpaper decode.
    WidgetsBinding.instance.deferFirstFrame();
    _accountStateFuture = _accountStore.loadState(AccountProvider.cup);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preparingBackground) {
      _preparingBackground = false;
      _prepareBackground();
    }
  }

  Future<void> _prepareBackground() async {
    try {
      await _themeController.load();
      if (!mounted) return;
      final bytes = _themeController.backgroundImageBytes;
      if (bytes != null) {
        await precacheImage(MemoryImage(bytes), context);
      }
    } catch (_) {
      // A missing preference file must not leave the native launch screen stuck.
    } finally {
      WidgetsBinding.instance.allowFirstFrame();
    }
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (context, _) {
          return MaterialApp(
            title: '石大课表',
            debugShowCheckedModeBanner: false,
            themeMode: _themeController.themeMode,
            // Do not animate an opaque scaffold over the newly decoded wallpaper.
            themeAnimationDuration: Duration.zero,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;
              final showBackground =
                  _themeController.hasBackgroundImage &&
                  brightness == Brightness.dark;
              final baseColor = brightness == Brightness.dark
                  ? const Color(0xFF101116)
                  : const Color(0xFFFFFFFF);
              return Stack(
                fit: StackFit.expand,
                children: [
                  AppBackgroundLayer(
                    settings: _themeController.background,
                    imageBytes: showBackground
                        ? _themeController.backgroundImageBytes
                        : null,
                    baseColor: baseColor,
                  ),
                  ?child,
                ],
              );
            },
            home: FutureBuilder<ManagedAccountState>(
              future: _accountStateFuture,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (snapshot.connectionState != ConnectionState.done) {
                  return Scaffold(
                    backgroundColor: Colors.transparent,
                    body: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (state == null || !state.hasCredentials) {
                  return CupLoginPage(
                    store: _accountStore,
                    onLoginSuccess: (_) {
                      setState(() {
                        _accountStateFuture = _accountStore.loadState(
                          AccountProvider.cup,
                        );
                      });
                    },
                  );
                }
                return const SchedulePage();
              },
            ),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = _themeController.hasBackgroundImage && isDark
        ? Colors.transparent
        : isDark
        ? const Color(0xFF101116)
        : const Color(0xFFFFFFFF);
    final foreground = isDark
        ? const Color(0xFFF0F1F7)
        : const Color(0xFF101525);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFFB51E23),
            brightness: brightness,
          ).copyWith(
            // Neutral, high-contrast text instead of the seed's pink-tinted colors.
            primary: isDark ? const Color(0xFFF5F7FA) : const Color(0xFF9C1920),
            onPrimary: isDark ? const Color(0xFF15171C) : Colors.white,
            secondary: isDark
                ? const Color(0xFFE2E7F0)
                : const Color(0xFF424B5C),
            onSecondary: isDark ? const Color(0xFF15171C) : Colors.white,
            primaryContainer: isDark
                ? const Color(0xFF303641)
                : const Color(0xFFE9EDF4),
            onPrimaryContainer: foreground,
            secondaryContainer: isDark
                ? const Color(0xFF303641)
                : const Color(0xFFE9EDF4),
            onSecondaryContainer: foreground,
            surface: isDark ? const Color(0xFF181B22) : Colors.white,
            onSurface: foreground,
            onSurfaceVariant: isDark
                ? const Color(0xFFCDD3DF)
                : const Color(0xFF4B5565),
            surfaceContainerLowest: isDark
                ? const Color(0xFF101116)
                : Colors.white,
            surfaceContainerLow: isDark
                ? const Color(0xFF1C1F27)
                : const Color(0xFFF7F8FA),
            surfaceContainer: isDark
                ? const Color(0xFF222630)
                : const Color(0xFFF0F2F6),
            surfaceContainerHigh: isDark
                ? const Color(0xFF292E39)
                : const Color(0xFFE9EDF3),
            surfaceContainerHighest: isDark
                ? const Color(0xFF343B48)
                : const Color(0xFFE2E7EE),
            surfaceTint: Colors.transparent,
            outline: isDark ? const Color(0xFF929CAE) : const Color(0xFF737E90),
          ),
      fontFamily: 'sans',
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: background,
        foregroundColor: foreground,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? const Color(0xFF18191F)
            : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFFE6E7EF)
            : const Color(0xFF18191F),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF101116) : const Color(0xFFF0F1F7),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
