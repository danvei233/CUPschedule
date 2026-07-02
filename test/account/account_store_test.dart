import 'package:blackbook/src/account/account_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('requires a saved password for complete credentials', () async {
    SharedPreferences.setMockInitialValues({'account.cup.username': 'student'});
    const store = AccountStore();

    final state = await store.loadState(AccountProvider.cup);

    expect(state.username, 'student');
    expect(state.hasCredentials, isFalse);
  });

  test('keeps credentials valid when the saved session is expired', () async {
    SharedPreferences.setMockInitialValues({});
    const store = AccountStore();
    final now = DateTime.now();

    await store.saveCredentials(
      const ManagedAccountCredentials(
        provider: AccountProvider.cup,
        username: 'student',
        password: 'secret',
      ),
    );
    await store.saveSession(
      ManagedPlatformSession(
        provider: AccountProvider.cup,
        cookies: const {'SESSION': 'old'},
        savedAt: now.subtract(const Duration(hours: 8)),
        expiresAt: now.subtract(const Duration(hours: 1)),
      ),
    );

    final state = await store.loadState(AccountProvider.cup);

    expect(state.hasCredentials, isTrue);
    expect(state.hasSession, isTrue);
    expect(state.sessionExpired, isTrue);
  });

  test('stores platform sessions and reports expiry', () async {
    SharedPreferences.setMockInitialValues({});
    const store = AccountStore();
    final now = DateTime.now();

    await store.saveSession(
      ManagedPlatformSession(
        provider: AccountProvider.cup,
        cookies: const {'SESSION': 'abc'},
        savedAt: now,
        expiresAt: now.add(const Duration(hours: 6)),
      ),
    );

    final session = await store.loadSession(AccountProvider.cup);
    final state = await store.loadState(AccountProvider.cup);

    expect(session?.cookies, {'SESSION': 'abc'});
    expect(state.hasSession, isTrue);
    expect(state.sessionExpired, isFalse);
  });
}
