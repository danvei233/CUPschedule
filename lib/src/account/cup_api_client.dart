import 'dart:convert';

import 'package:gm_crypto/gm_crypto.dart';
import 'package:http/http.dart' as http;

import 'account_store.dart';

class CupApiClient {
  CupApiClient({http.Client? httpClient, Map<String, String>? initialCookies})
    : _http = httpClient ?? http.Client() {
    if (initialCookies != null) {
      _cookies.addAll(initialCookies);
    }
  }

  final http.Client _http;
  final Map<String, String> _cookies = {};

  static const _bkOrigin = 'https://bk.cup.edu.cn';
  static const _ssoOrigin = 'https://sso.cup.edu.cn';
  static const _courseTablePath = '/student/for-std/course-table';

  Map<String, String> get cookieSnapshot => Map.unmodifiable(_cookies);

  Future<CupCourseTableSession> login(
    ManagedAccountCredentials credentials,
  ) async {
    if (!credentials.isComplete) {
      throw StateError('账号和密码都要填');
    }

    final loginEntry = await _send(
      'GET',
      Uri.parse('$_bkOrigin/student/sso/login'),
      followRedirects: false,
    );
    final ssoUrl = _absoluteUrl(
      loginEntry.headers['location'],
      Uri.parse('$_bkOrigin/student/sso/login'),
    );
    if (ssoUrl == null || !ssoUrl.host.contains('sso.cup.edu.cn')) {
      throw StateError('没有拿到统一认证登录地址');
    }

    final loginPage = await _send('GET', ssoUrl);
    final loginHtml = utf8.decode(loginPage.bodyBytes);
    final form = _parseLoginForm(loginHtml);
    final encryptedPassword = _encryptPassword(
      credentials.password,
      form.publicKeyBase64,
    );

    final loginPost = await _send(
      'POST',
      Uri.parse('$_ssoOrigin/login'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': _ssoOrigin,
        'Referer': ssoUrl.toString(),
      },
      bodyFields: {
        ...form.hiddenFields,
        'username': credentials.username,
        'password': encryptedPassword,
        'loginType': 'username_password',
        'rememberMe': 'true',
        'submit': '登录',
      },
      followRedirects: false,
    );

    final afterLoginLocation = loginPost.headers['location'];
    if (afterLoginLocation == null || afterLoginLocation.isEmpty) {
      final text = utf8.decode(loginPost.bodyBytes, allowMalformed: true);
      final message = _loginErrorMessage(text);
      if (isCupCredentialErrorMessage(message)) {
        throw CupCredentialsException(message!);
      }
      throw StateError(message ?? '统一认证没有返回登录跳转');
    }

    await _followRedirects(
      _absoluteUrl(afterLoginLocation, Uri.parse('$_ssoOrigin/login'))!,
      maxHops: 8,
    );

    final page = await _send('GET', Uri.parse('$_bkOrigin$_courseTablePath'));
    final pageText = utf8.decode(page.bodyBytes, allowMalformed: true);
    _throwIfLoggedOut(page, pageText, '教务会话不可用，请重新登录');
    return _parseCourseTableSession(pageText);
  }

  Future<CupCourseTableSession> loadCourseTableSession() async {
    final page = await _send('GET', Uri.parse('$_bkOrigin$_courseTablePath'));
    final pageText = utf8.decode(page.bodyBytes, allowMalformed: true);
    _throwIfLoggedOut(page, pageText, '教务会话已过期');
    return _parseCourseTableSession(pageText);
  }

  Future<CupSchedulePayload> fetchSchedule(
    CupCourseTableSession session,
    CupSemesterOption semester,
  ) async {
    final getDataUri =
        Uri.parse('$_bkOrigin/student/for-std/course-table/get-data').replace(
          queryParameters: {
            'semesterId': semester.id.toString(),
            'dataId': session.personId.toString(),
            'bizTypeId': session.bizTypeId.toString(),
          },
        );
    final getDataRes = await _send('GET', getDataUri);
    _throwIfLoggedOut(getDataRes, utf8.decode(getDataRes.bodyBytes), '教务会话已过期');
    _throwIfHttpFailed(getDataRes, '课表参数请求失败');

    final printDataUri =
        Uri.parse(
          '$_bkOrigin/student/for-std/course-table/semester/${semester.id}/print-data',
        ).replace(
          queryParameters: {
            'semesterId': semester.id.toString(),
            'hasExperiment': 'true',
          },
        );
    final printDataRes = await _send('GET', printDataUri);
    final printDataText = utf8.decode(printDataRes.bodyBytes);
    _throwIfLoggedOut(printDataRes, printDataText, '教务会话已过期');
    _throwIfHttpFailed(printDataRes, '完整课表请求失败');
    final printData = jsonDecode(printDataText) as Map<String, dynamic>;
    final tables = printData['studentTableVms'] as List<dynamic>? ?? const [];
    if (tables.isEmpty) {
      throw StateError('该学期没有返回学生课表数据');
    }

    final semesterJson = semester.toJson();

    return CupSchedulePayload(
      semester: semester,
      semesterJson: semesterJson,
      printDataJson: printData,
    );
  }

  Future<bool> probe(ManagedAccountCredentials credentials) async {
    await login(credentials);
    return true;
  }

  void close() => _http.close();

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? bodyFields,
    bool followRedirects = true,
  }) async {
    final request = http.Request(method, uri);
    request.followRedirects = followRedirects;
    request.headers.addAll({
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.7',
      if (_cookies.isNotEmpty) 'Cookie': _cookieHeader,
      ...?headers,
    });
    if (bodyFields != null) {
      request.bodyFields = bodyFields;
    }
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    _storeCookies(response);
    return response;
  }

  Future<http.Response> _followRedirects(
    Uri uri, {
    required int maxHops,
  }) async {
    var current = uri;
    for (var i = 0; i < maxHops; i++) {
      final response = await _send('GET', current, followRedirects: false);
      if (!_isRedirect(response.statusCode)) {
        return response;
      }
      final next = _absoluteUrl(response.headers['location'], current);
      if (next == null) {
        return response;
      }
      current = next;
    }
    throw StateError('统一认证跳转次数过多');
  }

  CupCourseTableSession parseCourseTableSessionForTest(String html) {
    return _parseCourseTableSession(html);
  }

  CupCourseTableSession _parseCourseTableSession(String html) {
    final semestersRaw = _extractJsonAssignment(html, 'semesters');
    final currentRaw = _extractObjectAssignment(html, 'currentSemester');
    final personId = _extractIntAssignment(html, 'personId');
    final bizTypeId =
        _extractIntAssignment(html, 'bizTypeId') ??
        _extractConstIntAssignment(html, 'bizTypeId') ??
        2;

    if (semestersRaw == null || personId == null) {
      throw StateError('没有从教务课表页识别到学生课表参数');
    }
    final rawSemesters = jsonDecode(semestersRaw) as List<dynamic>;
    final semesters =
        rawSemesters
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => CupSemesterOption.fromJson(item.cast()))
            .toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate));

    CupSemesterOption? currentSemester;
    if (currentRaw != null) {
      try {
        currentSemester = CupSemesterOption.fromJson(
          jsonDecode(currentRaw.replaceAll("'", '"')) as Map<String, dynamic>,
        );
      } on Object {
        currentSemester = null;
      }
    }
    final session = CupCourseTableSession(
      personId: personId,
      bizTypeId: bizTypeId,
      semesters: semesters,
      currentSemesterId: currentSemester?.id,
    );
    return session;
  }

  CupLoginForm _parseLoginForm(String html) {
    final publicKey = RegExp(
      r'"sm2"\s*:\s*\{[\s\S]*?"publicKey"\s*:\s*"([^"]+)"',
    ).firstMatch(html)?.group(1);
    if (publicKey == null || publicKey.isEmpty) {
      throw StateError('没有识别到统一认证 SM2 公钥');
    }

    final hiddenFields = <String, String>{};
    final inputPattern = RegExp(
      r'<input\b[^>]*name="([^"]+)"[^>]*>',
      caseSensitive: false,
    );
    for (final match in inputPattern.allMatches(html)) {
      final input = match.group(0)!;
      final name = match.group(1)!;
      final value =
          RegExp(
            r'value="([^"]*)"',
            caseSensitive: false,
          ).firstMatch(input)?.group(1) ??
          '';
      hiddenFields[name] = _decodeHtmlAttribute(value);
    }
    return CupLoginForm(
      publicKeyBase64: publicKey.replaceAll(r'\/', '/'),
      hiddenFields: hiddenFields,
    );
  }

  String _encryptPassword(String password, String publicKeyBase64) {
    final decodedPublicKey = _bytesToHex(base64Decode(publicKeyBase64));
    final publicKeyHex = decodedPublicKey.startsWith('04')
        ? decodedPublicKey
        : '04$decodedPublicKey';
    final cipherHex = SM2.encrypt(password, publicKeyHex, cipherMode: C1C3C2);
    return base64Encode(_hexToBytes(cipherHex));
  }

  void _throwIfHttpFailed(http.Response response, String prefix) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$prefix：HTTP ${response.statusCode}');
    }
  }

  void _throwIfLoggedOut(http.Response response, String text, String message) {
    if (_isLoggedOutResponse(response, text)) {
      throw CupSessionExpiredException(message);
    }
  }

  bool _isLoggedOutResponse(http.Response response, String text) {
    final uri = _finalUri(response);
    return uri.path.contains('/student/login') ||
        uri.path.contains('/student/sso/login') ||
        uri.host.contains('sso.cup.edu.cn') ||
        _htmlTitle(text) == '登入页面';
  }

  Uri? _absoluteUrl(String? value, Uri base) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return base.resolve(value);
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  void _storeCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return;
    }
    for (final cookie in _splitSetCookie(raw)) {
      final pair = cookie.split(';').first;
      final index = pair.indexOf('=');
      if (index <= 0) {
        continue;
      }
      _cookies[pair.substring(0, index)] = pair.substring(index + 1);
    }
  }

  List<String> _splitSetCookie(String raw) {
    final cookies = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char == ',' && i + 1 < raw.length) {
        final tail = raw.substring(i + 1);
        if (RegExp(r'^\s*[^=;,\s]+=').hasMatch(tail)) {
          cookies.add(buffer.toString());
          buffer.clear();
          continue;
        }
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) {
      cookies.add(buffer.toString());
    }
    return cookies;
  }

  String get _cookieHeader =>
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  Uri _finalUri(http.Response response) =>
      response.request?.url ?? Uri.parse(_bkOrigin);

  String? _htmlTitle(String text) {
    return RegExp(
      r'<title[^>]*>([\s\S]*?)<\/title>',
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.trim();
  }

  String? _loginErrorMessage(String html) {
    return RegExp(
      r'class="[^"]*error[^"]*"[^>]*>([\s\S]*?)<',
      caseSensitive: false,
    ).firstMatch(html)?.group(1)?.trim();
  }

  String? _extractJsonAssignment(String html, String name) {
    final pattern = RegExp(
      'var\\s+$name\\s*=\\s*JSON\\.parse\\(\\s*([\\\'"])([\\s\\S]*?)\\1\\s*\\)',
    );
    final encoded = pattern.firstMatch(html)?.group(2);
    if (encoded == null) {
      return null;
    }
    return jsonDecode('"$encoded"') as String;
  }

  String? _extractObjectAssignment(String html, String name) {
    final startPattern = RegExp('var\\s+$name\\s*=');
    final match = startPattern.firstMatch(html);
    if (match == null) {
      return null;
    }
    final start = html.indexOf('{', match.end);
    if (start < 0) {
      return null;
    }
    var depth = 0;
    var inString = false;
    var quote = '';
    for (var i = start; i < html.length; i++) {
      final char = html[i];
      if (inString) {
        if (char == r'\') {
          i++;
          continue;
        }
        if (char == quote) {
          inString = false;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        inString = true;
        quote = char;
        continue;
      }
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return html.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  int? _extractIntAssignment(String html, String name) {
    final value = RegExp(
      'var\\s+$name\\s*=\\s*(\\d+)',
    ).firstMatch(html)?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  int? _extractConstIntAssignment(String html, String name) {
    final value = RegExp(
      'const\\s+$name\\s*=\\s*(\\d+)',
    ).firstMatch(html)?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  String _decodeHtmlAttribute(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  String _bytesToHex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  List<int> _hexToBytes(String hex) {
    final normalized = hex.length.isOdd ? '0$hex' : hex;
    return [
      for (var i = 0; i < normalized.length; i += 2)
        int.parse(normalized.substring(i, i + 2), radix: 16),
    ];
  }
}

bool isCupCredentialErrorMessage(String? message) {
  if (message == null || message.isEmpty) {
    return false;
  }
  return message.contains('用户名或密码') ||
      message.contains('账号或密码') ||
      message.contains('密码错误') ||
      message.contains('用户不存在') ||
      message.contains('账号不存在');
}

class CupCredentialsException implements Exception {
  const CupCredentialsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CupSessionExpiredException implements Exception {
  const CupSessionExpiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CupLoginForm {
  const CupLoginForm({
    required this.publicKeyBase64,
    required this.hiddenFields,
  });

  final String publicKeyBase64;
  final Map<String, String> hiddenFields;
}

class CupCourseTableSession {
  const CupCourseTableSession({
    required this.personId,
    required this.bizTypeId,
    required this.semesters,
    required this.currentSemesterId,
  });

  final int personId;
  final int bizTypeId;
  final List<CupSemesterOption> semesters;
  final int? currentSemesterId;
}

class CupSemesterOption {
  CupSemesterOption({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
  });

  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  factory CupSemesterOption.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value) {
      if (value is String) {
        return DateTime.parse(value.substring(0, 10));
      }
      if (value is Map) {
        final values = value['values'];
        if (values is List && values.length >= 3) {
          return DateTime(
            (values[0] as num).toInt(),
            (values[1] as num).toInt(),
            (values[2] as num).toInt(),
          );
        }
        final year = value['year'];
        final month = value['monthOfYear'];
        final day = value['dayOfMonth'];
        if (year is num && month is num && day is num) {
          return DateTime(year.toInt(), month.toInt(), day.toInt());
        }
      }
      throw StateError('学期日期格式不正确');
    }

    return CupSemesterOption(
      id: (json['id'] as num).toInt(),
      name: (json['nameZh'] ?? json['name'] ?? '') as String,
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nameZh': name,
      'name': name,
      'startDate': _dateText(startDate),
      'endDate': _dateText(endDate),
      'weekStartOnSunday': false,
      'sourceSemesterId': id,
    };
  }

  static String _dateText(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class CupSchedulePayload {
  const CupSchedulePayload({
    required this.semester,
    required this.semesterJson,
    required this.printDataJson,
  });

  final CupSemesterOption semester;
  final Map<String, dynamic> semesterJson;
  final Map<String, dynamic> printDataJson;
}
