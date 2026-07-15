import 'account_store.dart';
import 'cup_api_client.dart';

typedef CupApiClientFactory =
    CupApiClient Function(Map<String, String>? initialCookies);

CupApiClient createCupApiClient(Map<String, String>? initialCookies) {
  return CupApiClient(initialCookies: initialCookies);
}

class CupAccountService {
  const CupAccountService({
    this.store = const AccountStore(),
    this.clientFactory = createCupApiClient,
  });

  final AccountStore store;
  final CupApiClientFactory clientFactory;

  static const _sessionTtl = Duration(hours: 6);

  Future<CupSessionLease> acquireSession({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final storedSession = await store.loadSession(AccountProvider.cup);
      if (storedSession != null && storedSession.isUsable) {
        final client = clientFactory(storedSession.cookies);
        try {
          final session = await client.loadCourseTableSession();
          await _saveHealthySession(client);
          return CupSessionLease(
            client: client,
            session: session,
            renewed: false,
          );
        } on CupSessionExpiredException {
          client.close();
          await store.clearSession(AccountProvider.cup);
        } on Object {
          client.close();
          rethrow;
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
    final client = clientFactory(null);
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
      if (error is CupCredentialsException) {
        await store.clearSession(AccountProvider.cup);
      }
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
