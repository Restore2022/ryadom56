import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  ApiClient({this.baseUrl = 'http://192.168.0.110:8000/api'});

  /// На телефоне: IP ПК в Wi‑Fi. В эмуляторе: http://10.0.2.2:8000/api
  final String baseUrl;

  String get mediaBase {
    final uri = Uri.parse(baseUrl);
    final path = uri.path.endsWith('/api') ? uri.path.substring(0, uri.path.length - 4) : uri.path;
    return uri.replace(path: path.isEmpty ? '/' : path).toString().replaceAll(RegExp(r'/$'), '');
  }

  String resolveMedia(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$mediaBase$url';
    return '$mediaBase/$url';
  }

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

  String _formatDetail(dynamic detail) {
    if (detail is String) return detail;
    if (detail is List) {
      return detail.map((e) {
        if (e is Map) {
          final loc = (e['loc'] is List) ? (e['loc'] as List).join('.') : '';
          final msg = e['msg']?.toString() ?? e.toString();
          return loc.isEmpty ? msg : '$loc: $msg';
        }
        return e.toString();
      }).join('\n');
    }
    return detail?.toString() ?? 'Ошибка запроса';
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

    Map<String, dynamic>? cleanBody;
    if (body != null) {
      cleanBody = Map.fromEntries(body.entries.where((e) => e.value != null));
    }

    late http.Response res;
    switch (method) {
      case 'POST':
        res = await http.post(uri, headers: headers, body: jsonEncode(cleanBody));
        break;
      case 'PATCH':
        res = await http.patch(uri, headers: headers, body: jsonEncode(cleanBody));
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
      default:
        res = await http.get(uri, headers: headers);
    }
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final data = jsonDecode(res.body);
        detail = _formatDetail(data['detail']);
      } catch (_) {}
      throw Exception(detail);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> uploadListingImages(int listingId, List<String> filePaths) async {
    final uri = Uri.parse('$baseUrl/listings/$listingId/images');
    final req = http.MultipartRequest('POST', uri);
    final t = await token;
    if (t != null) req.headers['Authorization'] = 'Bearer $t';

    for (final path in filePaths) {
      final lower = path.toLowerCase();
      MediaType type;
      if (lower.endsWith('.png')) {
        type = MediaType('image', 'png');
      } else if (lower.endsWith('.webp')) {
        type = MediaType('image', 'webp');
      } else {
        type = MediaType('image', 'jpeg');
      }
      req.files.add(await http.MultipartFile.fromPath('files', path, contentType: type));
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final data = jsonDecode(res.body);
        detail = _formatDetail(data['detail']);
      } catch (_) {}
      throw Exception(detail);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
