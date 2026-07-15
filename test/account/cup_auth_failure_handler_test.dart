import 'package:blackbook/src/account/account_store.dart';
import 'package:blackbook/src/account/cup_auth_failure_handler.dart';
import 'package:blackbook/src/account/cup_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('credential failure offers retry without logging out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const store = AccountStore();
    await _saveCredentials(store);
    CupAuthFailureAction? result;
    await tester.pumpWidget(
      _HandlerApp(
        onPressed: (context) async {
          result = await handleCupAuthFailure(
            context,
            const CupCredentialsException('密码错误'),
            store: store,
          );
        },
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
    expect(find.text('登录信息错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('登出'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(result, CupAuthFailureAction.retry);
    expect((await store.loadState(AccountProvider.cup)).hasCredentials, isTrue);
  });

  testWidgets('credentials are cleared only after choosing logout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const store = AccountStore();
    await _saveCredentials(store);
    CupAuthFailureAction? result;
    await tester.pumpWidget(
      _HandlerApp(
        onPressed: (context) async {
          result = await handleCupAuthFailure(
            context,
            const CupCredentialsException('密码错误'),
            store: store,
          );
        },
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登出'));
    await tester.pumpAndSettle();

    expect(result, CupAuthFailureAction.loggedOut);
    expect(
      (await store.loadState(AccountProvider.cup)).hasCredentials,
      isFalse,
    );
  });

  testWidgets('network failure only shows a lightweight notice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _HandlerApp(
        onPressed: (context) async {
          await handleCupAuthFailure(context, http.ClientException('offline'));
        },
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pump();

    expect(find.text('登录失败，请检查网络'), findsOneWidget);
    expect(find.text('登录信息错误'), findsNothing);
  });
}

Future<void> _saveCredentials(AccountStore store) {
  return store.saveCredentials(
    const ManagedAccountCredentials(
      provider: AccountProvider.cup,
      username: 'student',
      password: 'secret',
    ),
  );
}

class _HandlerApp extends StatelessWidget {
  const _HandlerApp({required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('触发'),
          ),
        ),
      ),
    );
  }
}
