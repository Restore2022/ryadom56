import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  ApiClient({this.baseUrl = 'http://192.168.0.110:8000/api'});

  /// На телефоне: IP ПК в Wi‑Fi. В эмуляторе: http://10.0.2.2:8000/api
  final String baseUrl;

  Future<String?> get token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> setToken(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('token');
    } else {
      await prefs.setString('token', value);
    }
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final t = await token;
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }
    late http.Response res;
    switch (method) {
      case 'POST':
        res = await http.post(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PATCH':
        res = await http.patch(uri, headers: headers, body: jsonEncode(body));
        break;
      default:
        res = await http.get(uri, headers: headers);
    }
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final data = jsonDecode(res.body);
        detail = data['detail']?.toString() ?? res.body;
      } catch (_) {}
      throw Exception(detail);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}
