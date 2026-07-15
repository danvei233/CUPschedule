import 'package:blackbook/src/account/account_store.dart';
import 'package:blackbook/src/account/cup_account_service.dart';
import 'package:blackbook/src/account/cup_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const credentials = ManagedAccountCredentials(
    provider: AccountProvider.cup,
    username: 'student',
    password: 'secret',
  );

  test(
    'keeps credentials and cookies when session probe has network error',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = AccountStore();
      await store.saveCredentials(credentials);
      await store.saveSession(_session(expiresIn: const Duration(hours: 1)));
      final clients = <_FakeCupApiClient>[
        _FakeCupApiClient(
          onLoad: () async => throw http.ClientException('offline'),
        ),
      ];
      final service = CupAccountService(
        store: store,
        clientFactory: (_) => clients.removeAt(0),
      );

      await expectLater(
        service.acquireSession(),
        throwsA(isA<http.ClientException>()),
      );

      expect(
        (await store.loadCredentials(AccountProvider.cup))?.password,
        'secret',
      );
      expect((await store.loadSession(AccountProvider.cup))?.cookies, {
        'SESSION': 'saved',
      });
    },
  );

  test(
    'automatically renews only after server reports an expired session',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = AccountStore();
      await store.saveCredentials(credentials);
      await store.saveSession(_session(expiresIn: const Duration(hours: 1)));
      final clients = <_FakeCupApiClient>[
        _FakeCupApiClient(
          onLoad: () async => throw const CupSessionExpiredException('会话已过期'),
        ),
        _FakeCupApiClient(
          cookies: const {'SESSION': 'renewed'},
          onLogin: (_) async => _courseTableSession,
        ),
      ];
      final service = CupAccountService(
        store: store,
        clientFactory: (_) => clients.removeAt(0),
      );

      final lease = await service.acquireSession();
      addTearDown(lease.client.close);

      expect(lease.renewed, isTrue);
      expect((await store.loadSession(AccountProvider.cup))?.cookies, {
        'SESSION': 'renewed',
      });
      expect(
        (await store.loadCredentials(AccountProvider.cup))?.password,
        'secret',
      );
    },
  );

  test(
    'keeps credentials when automatic renewal rejects the password',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = AccountStore();
      await store.saveCredentials(credentials);
      await store.saveSession(_session(expiresIn: const Duration(hours: -1)));
      final service = CupAccountService(
        store: store,
        clientFactory: (_) => _FakeCupApiClient(
          onLogin: (_) async => throw const CupCredentialsException('密码错误'),
        ),
      );

      await expectLater(
        service.acquireSession(),
        throwsA(isA<CupCredentialsException>()),
      );

      expect(
        (await store.loadCredentials(AccountProvider.cup))?.password,
        'secret',
      );
    },
  );

  test('recognizes only explicit credential error messages', () {
    expect(isCupCredentialErrorMessage('用户名或密码错误'), isTrue);
    expect(isCupCredentialErrorMessage('该用户不存在'), isTrue);
    expect(isCupCredentialErrorMessage('统一认证服务暂时不可用'), isFalse);
    expect(isCupCredentialErrorMessage(null), isFalse);
  });
}

ManagedPlatformSession _session({required Duration expiresIn}) {
  final now = DateTime.now();
  return ManagedPlatformSession(
    provider: AccountProvider.cup,
    cookies: const {'SESSION': 'saved'},
    savedAt: now,
    expiresAt: now.add(expiresIn),
  );
}

const _courseTableSession = CupCourseTableSession(
  personId: 1,
  bizTypeId: 2,
  semesters: [],
  currentSemesterId: null,
);

class _FakeCupApiClient extends CupApiClient {
  _FakeCupApiClient({this.cookies = const {}, this.onLoad, this.onLogin});

  final Map<String, String> cookies;
  final Future<CupCourseTableSession> Function()? onLoad;
  final Future<CupCourseTableSession> Function(
    ManagedAccountCredentials credentials,
  )?
  onLogin;

  @override
  Map<String, String> get cookieSnapshot => cookies;

  @override
  Future<CupCourseTableSession> loadCourseTableSession() {
    return onLoad?.call() ?? Future.value(_courseTableSession);
  }

  @override
  Future<CupCourseTableSession> login(ManagedAccountCredentials credentials) {
    return onLogin?.call(credentials) ?? Future.value(_courseTableSession);
  }
}
