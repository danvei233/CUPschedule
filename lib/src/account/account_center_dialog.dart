import 'package:flutter/material.dart';

import '../app_palette.dart';
import 'account_store.dart';
import 'cup_account_service.dart';

typedef AccountLoginSuccessCallback = void Function(ManagedAccountState state);

Future<void> showAccountCenterDock(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (context) => const AccountCenterDock(),
  );
}

class AccountCenterDock extends StatefulWidget {
  const AccountCenterDock({super.key, this.store = const AccountStore()});

  final AccountStore store;

  @override
  State<AccountCenterDock> createState() => _AccountCenterDockState();
}

class _AccountCenterDockState extends State<AccountCenterDock> {
  late Future<ManagedAccountState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = widget.store.loadState(AccountProvider.cup);
  }

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomPadding),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: FutureBuilder<ManagedAccountState>(
                future: _stateFuture,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '账号管理',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: palette.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                            iconSize: 22,
                            color: palette.subtle,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (snapshot.connectionState != ConnectionState.done)
                        const SizedBox(
                          height: 86,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (state == null || !state.hasCredentials)
                        _NotLoggedInPanel(onLogin: _openLogin)
                      else
                        _CupAccountPanel(
                          state: state,
                          onRelogin: _openLogin,
                          onLogout: _logout,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CupLoginPage(
          store: widget.store,
          onLoginSuccess: (_) => Navigator.of(context).pop(),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _stateFuture = widget.store.loadState(AccountProvider.cup);
    });
  }

  Future<void> _logout() async {
    await widget.store.clear(AccountProvider.cup);
    if (!mounted) {
      return;
    }
    await _openLogin();
  }
}

class CupLoginPage extends StatefulWidget {
  const CupLoginPage({
    super.key,
    this.store = const AccountStore(),
    this.onLoginSuccess,
  });

  final AccountStore store;
  final AccountLoginSuccessCallback? onLoginSuccess;

  @override
  State<CupLoginPage> createState() => _CupLoginPageState();
}

class _CupLoginPageState extends State<CupLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  var _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Scaffold(
      backgroundColor: palette.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              children: [
                Center(child: _CupLogo(size: 62)),
                const SizedBox(height: 18),
                Text(
                  '中石大登录',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '使用统一认证账号建立 API 会话',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.subtle,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                _LoginTextField(
                  controller: _usernameController,
                  hintText: '统一认证账号',
                  icon: Icons.person_outline,
                  obscureText: false,
                ),
                const SizedBox(height: 10),
                _LoginTextField(
                  controller: _passwordController,
                  hintText: '密码',
                  icon: Icons.lock_outline,
                  obscureText: true,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  _InlineMessage(message: _message!),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.onPrimary,
                          ),
                        )
                      : const Icon(Icons.login, size: 18),
                  label: Text(_busy ? '正在校验' : '登录'),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.onPrimary,
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadSavedUsername() async {
    final credentials = await widget.store.loadCredentials(AccountProvider.cup);
    if (!mounted || credentials == null) {
      return;
    }
    _usernameController.text = credentials.username;
  }

  Future<void> _login() async {
    final credentials = ManagedAccountCredentials(
      provider: AccountProvider.cup,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (!credentials.isComplete) {
      setState(() => _message = '账号和密码都要填');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final lease = await CupAccountService(
        store: widget.store,
      ).loginAndSave(credentials);
      lease.client.close();
      final state = await widget.store.loadState(AccountProvider.cup);
      if (!mounted) {
        return;
      }
      widget.onLoginSuccess?.call(state);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _message = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
      });
    }
  }
}

class _NotLoggedInPanel extends StatelessWidget {
  const _NotLoggedInPanel({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Row(
      children: [
        _CupLogo(size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '未登录中石大',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        FilledButton(onPressed: onLogin, child: const Text('登录')),
      ],
    );
  }
}

class _CupAccountPanel extends StatelessWidget {
  const _CupAccountPanel({
    required this.state,
    required this.onRelogin,
    required this.onLogout,
  });

  final ManagedAccountState state;
  final VoidCallback onRelogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final statusText = state.hasSession && !state.sessionExpired
        ? '会话可用'
        : state.sessionExpired
        ? '会话已过期'
        : state.lastMessage.isNotEmpty
        ? state.lastMessage
        : '未建立会话';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _CupLogo(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.username,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _StatusDot(status: state.lastStatus),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRelogin,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新登录'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('登出'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.danger,
                  foregroundColor: palette.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CupLogo extends StatelessWidget {
  const _CupLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Image.asset(
            'assets/account/cup_favicon.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.obscureText,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: false,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: TextStyle(color: palette.muted),
          prefixIcon: Icon(icon, size: 18, color: palette.subtle),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          filled: true,
          fillColor: palette.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: palette.danger,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final AccountLoginStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final color = switch (status) {
      AccountLoginStatus.success => palette.success,
      AccountLoginStatus.failed => palette.danger,
      AccountLoginStatus.unknown => palette.muted,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
