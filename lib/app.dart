import 'package:flutter/material.dart';

import 'src/account/account_center_dialog.dart';
import 'src/account/account_store.dart';
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

  @override
  void initState() {
    super.initState();
    _themeController = AppThemeController();
    _themeController.load();
    _accountStateFuture = _accountStore.loadState(AccountProvider.cup);
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
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: FutureBuilder<ManagedAccountState>(
              future: _accountStateFuture,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (snapshot.connectionState != ConnectionState.done) {
                  return Scaffold(
                    backgroundColor: _buildTheme(
                      _themeController.themeMode == ThemeMode.dark
                          ? Brightness.dark
                          : Brightness.light,
                    ).scaffoldBackgroundColor,
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
    final background = isDark
        ? const Color(0xFF101116)
        : const Color(0xFFFFFFFF);
    final foreground = isDark
        ? const Color(0xFFF0F1F7)
        : const Color(0xFF101525);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB51E23),
        brightness: brightness,
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
