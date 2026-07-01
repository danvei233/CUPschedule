import 'package:blackbook/src/account/account_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
