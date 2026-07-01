import 'account_store.dart';
import 'cup_api_client.dart';

class CupAccountService {
  const CupAccountService({this.store = const AccountStore()});

  final AccountStore store;

  static const _sessionTtl = Duration(hours: 6);

  Future<CupSessionLease> acquireSession({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final storedSession = await store.loadSession(AccountProvider.cup);
      if (storedSession != null && storedSession.isUsable) {
        final client = CupApiClient(initialCookies: storedSession.cookies);
        try {
          final session = await client.loadCourseTableSession();
          await _saveHealthySession(client);
          return CupSessionLease(
            client: client,
            session: session,
            renewed: false,
          );
        } on Object {
          client.close();
          await store.clearSession(AccountProvider.cup);
        }
      }
    }

    return _loginAndSave();
  }

  Future<CupSessionLease> refreshSession() => _loginAndSave();

  Future<CupSessionLease> _loginAndSave() async {
    final credentials = await store.loadCredentials(AccountProvider.cup);
    if (credentials == null || !credentials.isComplete) {
      throw StateError('账号中心没有完整的中石大账号');
    }

    return loginAndSave(credentials);
  }

  Future<CupSessionLease> loginAndSave(
    ManagedAccountCredentials credentials,
  ) async {
    final client = CupApiClient();
    try {
      final session = await client.login(credentials);
      await store.saveCredentials(credentials);
      await _saveHealthySession(client);
      await store.saveCheckResult(
        provider: AccountProvider.cup,
        status: AccountLoginStatus.success,
        message: '中石大会话可用',
      );
      return CupSessionLease(client: client, session: session, renewed: true);
    } on Object catch (error) {
      client.close();
      final message = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '');
      await store.clearSession(AccountProvider.cup);
      await store.saveCheckResult(
        provider: AccountProvider.cup,
        status: AccountLoginStatus.failed,
        message: message,
      );
      rethrow;
    }
  }

  Future<void> _saveHealthySession(CupApiClient client) {
    final now = DateTime.now();
    return store.saveSession(
      ManagedPlatformSession(
        provider: AccountProvider.cup,
        cookies: client.cookieSnapshot,
        savedAt: now,
        expiresAt: now.add(_sessionTtl),
      ),
    );
  }
}

class CupSessionLease {
  const CupSessionLease({
    required this.client,
    required this.session,
    required this.renewed,
  });

  final CupApiClient client;
  final CupCourseTableSession session;
  final bool renewed;
}
