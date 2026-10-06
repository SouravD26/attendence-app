import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Thin HTTP layer for the HRMS API.
///
/// Handles the three things every call needs: the bearer token, the
/// mod_rewrite fallback, and turning a non-2xx / `success:false` body into an
/// [ApiException] the UI can show verbatim.
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl;

  /// Override for local testing:
  /// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8099`
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://helpdesk.sanmarg.in/api/v1',
  );

  static const _tokenKey = 'hrms_auth_token';

  final String baseUrl;

  String? _token;
  bool get hasToken => _token != null;

  /// The server has no mod_rewrite (verified against the live host), so start
  /// in `index.php?route=` mode rather than burning a 404 on every first call.
  /// If pretty URLs are enabled later, flip this to false — a 404 still makes
  /// the client fall back automatically, so both configurations work.
  bool _useRouteFallback = true;

  // ---------------------------------------------------------------- session

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  // ---------------------------------------------------------------- requests

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final params = <String, String>{
      for (final e in (query ?? {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };

    if (_useRouteFallback) {
      return Uri.parse('$baseUrl/index.php')
          .replace(queryParameters: {'route': path, ...params});
    }
    return Uri.parse('$baseUrl/$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send(path, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) =>
      _send(path, body: body ?? const {});

  Future<Map<String, dynamic>> _send(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    bool allowRetry = true,
  }) async {
    late final http.Response res;
    try {
      res = body == null
          ? await http
              .get(_uri(path, query), headers: _headers)
              .timeout(const Duration(seconds: 25))
          : await http
              .post(_uri(path), headers: _headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw const ApiException(
        'Could not reach the server. Check your connection.',
      );
    }

    // Pretty URLs unavailable -> switch to index.php?route= and retry once.
    if (res.statusCode == 404 && allowRetry && !_useRouteFallback) {
      _useRouteFallback = true;
      return _send(path, query: query, body: body, allowRetry: false);
    }

    if (res.statusCode == 401) {
      await setToken(null);
      throw const ApiException('Your session expired. Please sign in again.');
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      json = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      throw ApiException('Unexpected response from the server (${res.statusCode}).');
    }

    final ok = res.statusCode >= 200 &&
        res.statusCode < 300 &&
        json['success'] != false &&
        json['status'] != 'error';

    if (!ok) {
      throw ApiException(
        (json['message'] ?? json['error'] ?? 'Request failed.').toString(),
      );
    }
    return json;
  }
}

/// Pulls the payload out regardless of whether the server wraps it in `data`.
Map<String, dynamic> payloadOf(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map<String, dynamic>) return data;
  return json;
}

/// Same idea for list endpoints (`data`, `items`, or a bare array).
List<Map<String, dynamic>> listOf(Map<String, dynamic> json, [String? key]) {
  for (final candidate in [key, 'data', 'items', 'records', 'list']) {
    if (candidate == null) continue;
    final value = json[candidate];
    if (value is List) {
      return value.whereType<Map<String, dynamic>>().toList();
    }
    if (value is Map<String, dynamic>) {
      final nested = value[key ?? 'items'] ?? value['data'];
      if (nested is List) {
        return nested.whereType<Map<String, dynamic>>().toList();
      }
    }
  }
  return const [];
}

/// First non-null value among [keys] — the field names differ slightly across
/// endpoints, and this keeps the mapping readable instead of nested ternaries.
Object? pick(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v != null && v != '') return v;
  }
  return null;
}
