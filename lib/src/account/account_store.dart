import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum AccountProvider { cup, rainClassroom, xuexitong }

class ManagedAccountCredentials {
  const ManagedAccountCredentials({
    required this.provider,
    required this.username,
    required this.password,
  });

  final AccountProvider provider;
  final String username;
  final String password;

  bool get isComplete => username.isNotEmpty && password.isNotEmpty;
}

class ManagedAccountState {
  const ManagedAccountState({
    required this.provider,
    required this.username,
    required this.lastStatus,
    required this.lastMessage,
    required this.lastCheckedAt,
    required this.passwordSaved,
    required this.sessionSavedAt,
    required this.sessionExpiresAt,
  });

  final AccountProvider provider;
  final String username;
  final AccountLoginStatus lastStatus;
  final String lastMessage;
  final DateTime? lastCheckedAt;
  final bool passwordSaved;
  final DateTime? sessionSavedAt;
  final DateTime? sessionExpiresAt;

  bool get hasCredentials => username.isNotEmpty && passwordSaved;
  bool get hasSession => sessionSavedAt != null;
  bool get sessionExpired {
    final expiresAt = sessionExpiresAt;
    return expiresAt != null && DateTime.now().isAfter(expiresAt);
  }
}

enum AccountLoginStatus { unknown, success, failed }

class ManagedPlatformSession {
  const ManagedPlatformSession({
    required this.provider,
    required this.cookies,
    required this.savedAt,
    required this.expiresAt,
  });

  final AccountProvider provider;
  final Map<String, String> cookies;
  final DateTime savedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsable => cookies.isNotEmpty && !isExpired;
}

class AccountStore {
  const AccountStore();

  Future<ManagedAccountCredentials?> loadCredentials(
    AccountProvider provider,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final username = preferences.getString(_usernameKey(provider)) ?? '';
    final password = preferences.getString(_passwordKey(provider)) ?? '';
    if (username.isEmpty && password.isEmpty) {
      return null;
    }
    return ManagedAccountCredentials(
      provider: provider,
      username: username,
      password: password,
    );
  }

  Future<ManagedAccountState> loadState(AccountProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    final username = preferences.getString(_usernameKey(provider)) ?? '';
    final statusName = preferences.getString(_statusKey(provider));
    final checkedAtText = preferences.getString(_checkedAtKey(provider));
    final checkedAt = checkedAtText == null
        ? null
        : DateTime.tryParse(checkedAtText);
    return ManagedAccountState(
      provider: provider,
      username: username,
      lastStatus: _statusFromName(statusName),
      lastMessage: preferences.getString(_messageKey(provider)) ?? '',
      lastCheckedAt: checkedAt,
      passwordSaved:
          (preferences.getString(_passwordKey(provider)) ?? '').isNotEmpty,
      sessionSavedAt: _dateTimeFromText(
        preferences.getString(_sessionSavedAtKey(provider)),
      ),
      sessionExpiresAt: _dateTimeFromText(
        preferences.getString(_sessionExpiresAtKey(provider)),
      ),
    );
  }

  Future<List<ManagedAccountState>> loadStates() async {
    return [await loadState(AccountProvider.cup)];
  }

  Future<void> saveCredentials(ManagedAccountCredentials credentials) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _usernameKey(credentials.provider),
      credentials.username,
    );
    await preferences.setString(
      _passwordKey(credentials.provider),
      credentials.password,
    );
    await clearCheckResult(credentials.provider);
    await clearSession(credentials.provider);
  }

  Future<ManagedPlatformSession?> loadSession(AccountProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    final rawCookies = preferences.getString(_sessionCookiesKey(provider));
    final savedAt = _dateTimeFromText(
      preferences.getString(_sessionSavedAtKey(provider)),
    );
    final expiresAt = _dateTimeFromText(
      preferences.getString(_sessionExpiresAtKey(provider)),
    );
    if (rawCookies == null || savedAt == null || expiresAt == null) {
      return null;
    }
    final decoded = Map<String, dynamic>.from(
      rawCookies.isEmpty ? const <String, dynamic>{} : _decodeJson(rawCookies),
    );
    final cookies = decoded.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
    if (cookies.isEmpty) {
      return null;
    }
    return ManagedPlatformSession(
      provider: provider,
      cookies: cookies,
      savedAt: savedAt,
      expiresAt: expiresAt,
    );
  }

  Future<void> saveSession(ManagedPlatformSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _sessionCookiesKey(session.provider),
      _encodeJson(session.cookies),
    );
    await preferences.setString(
      _sessionSavedAtKey(session.provider),
      session.savedAt.toIso8601String(),
    );
    await preferences.setString(
      _sessionExpiresAtKey(session.provider),
      session.expiresAt.toIso8601String(),
    );
  }

  Future<void> clearSession(AccountProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionCookiesKey(provider));
    await preferences.remove(_sessionSavedAtKey(provider));
    await preferences.remove(_sessionExpiresAtKey(provider));
  }

  Future<void> saveCheckResult({
    required AccountProvider provider,
    required AccountLoginStatus status,
    required String message,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_statusKey(provider), status.name);
    await preferences.setString(_messageKey(provider), message);
    await preferences.setString(
      _checkedAtKey(provider),
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> clear(AccountProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_usernameKey(provider));
    await preferences.remove(_passwordKey(provider));
    await clearCheckResult(provider);
    await clearSession(provider);
  }

  Future<void> clearCheckResult(AccountProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_statusKey(provider));
    await preferences.remove(_messageKey(provider));
    await preferences.remove(_checkedAtKey(provider));
  }

  AccountLoginStatus _statusFromName(String? name) {
    for (final status in AccountLoginStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return AccountLoginStatus.unknown;
  }

  String _usernameKey(AccountProvider provider) {
    return 'account.${provider.name}.username';
  }

  String _passwordKey(AccountProvider provider) {
    return 'account.${provider.name}.password';
  }

  String _statusKey(AccountProvider provider) {
    return 'account.${provider.name}.status';
  }

  String _messageKey(AccountProvider provider) {
    return 'account.${provider.name}.message';
  }

  String _checkedAtKey(AccountProvider provider) {
    return 'account.${provider.name}.checked_at';
  }

  String _sessionCookiesKey(AccountProvider provider) {
    return 'account.${provider.name}.session.cookies';
  }

  String _sessionSavedAtKey(AccountProvider provider) {
    return 'account.${provider.name}.session.saved_at';
  }

  String _sessionExpiresAtKey(AccountProvider provider) {
    return 'account.${provider.name}.session.expires_at';
  }

  DateTime? _dateTimeFromText(String? value) {
    return value == null ? null : DateTime.tryParse(value);
  }

  Map<String, dynamic> _decodeJson(String value) {
    return Map<String, dynamic>.from(
      const JsonDecoder().convert(value) as Map<dynamic, dynamic>,
    );
  }

  String _encodeJson(Map<String, String> value) {
    return const JsonEncoder().convert(value);
  }
}
