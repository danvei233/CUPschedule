import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'account_store.dart';
import 'cup_api_client.dart';

enum CupAuthFailureAction { retry, loggedOut, dismissed }

Future<CupAuthFailureAction> handleCupAuthFailure(
  BuildContext context,
  Object error, {
  AccountStore store = const AccountStore(),
}) async {
  if (error is CupCredentialsException) {
    final retry = await showCupCredentialsErrorDialog(context);
    if (retry == true) {
      return CupAuthFailureAction.retry;
    }
    await store.clear(AccountProvider.cup);
    return CupAuthFailureAction.loggedOut;
  }

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(cupAuthFailureNotice(error)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  return CupAuthFailureAction.dismissed;
}

Future<bool?> showCupCredentialsErrorDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('登录信息错误'),
      content: const Text('保存的账号或密码无法通过统一认证，请重试或登出后重新填写。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('登出'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('重试'),
        ),
      ],
    ),
  );
}

String cupAuthFailureNotice(Object error) {
  if (error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return '登录失败，请检查网络';
  }
  final message = error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
  return message.isEmpty ? '登录失败，请稍后重试' : '登录失败：$message';
}
