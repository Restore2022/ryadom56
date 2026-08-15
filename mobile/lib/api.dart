import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.raw});

  final String message;
  final int? statusCode;
  final String? raw;

  @override
  String toString() => message;
}

const kProductionApiBase = 'https://legac.ru/api';

class ApiClient {
  ApiClient({this.baseUrl = kProductionApiBase});

  /// Прод: https://legac.ru/api. Локально: http://10.0.2.2:8000/api
  final String baseUrl;
  void Function()? onUnauthorized;

  /// Пользовательский текст: без «API», Wi‑Fi и технических деталей.
  static const offlineMessage =
      'Нет связи с сервером. Проверьте интернет и попробуйте снова.';

  static const noInternetMessage =
      'Нет интернета. Проверьте подключение и попробуйте снова.';

  static const serverUnreachableMessage =
      'Не удалось связаться с сервером. Попробуйте чуть позже.';

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
          final loc = (e['loc'] is List) ? (e['loc'] as List).skip(1).join('.') : '';
          final msg = e['msg']?.toString() ?? e.toString();
          final clean = msg.replaceFirst(RegExp(r'^Value error,\s*'), '');
          return loc.isEmpty ? clean : '$loc: $clean';
        }
        return e.toString();
      }).join('\n');
    }
    return detail?.toString() ?? 'Ошибка запроса';
  }

  String _messageForStatus(int code, String detail) {
    final d = detail.trim();
    switch (code) {
      case 401:
        if (d.contains('Неверный') || d.toLowerCase().contains('password') || d.contains('email')) {
          return d.isNotEmpty ? d : 'Неверный email или пароль';
        }
        return d.isNotEmpty && d.length < 120 ? d : 'Сессия истекла. Войдите снова';
      case 403:
        return d.isNotEmpty && d.length < 160 ? d : 'Нет доступа';
      case 404:
        return d.isNotEmpty && d.length < 160 ? d : 'Не найдено';
      case 408:
      case 504:
        return serverUnreachableMessage;
      case 413:
        return 'Файл слишком большой';
      case 422:
        return d.isNotEmpty ? d : 'Проверьте правильность заполнения полей';
      case 429:
        return 'Слишком много запросов. Подождите немного';
      case 500:
      case 502:
      case 503:
        return 'Ошибка сервера. Попробуйте позже';
      default:
        return d.isNotEmpty && !d.startsWith('<') && d.length < 240 ? d : 'Не удалось выполнить запрос';
    }
  }

  ApiException _fromResponse(http.Response res) {
    String detail = '';
    try {
      final data = jsonDecode(res.body);
      if (data is Map) detail = _formatDetail(data['detail']);
    } catch (_) {
      detail = '';
    }
    return ApiException(_messageForStatus(res.statusCode, detail), statusCode: res.statusCode, raw: detail);
  }

  ApiException _fromNetwork(Object e) {
    final raw = e.toString().toLowerCase();
    if (e is TimeoutException || raw.contains('timeout') || raw.contains('timed out')) {
      return ApiException(serverUnreachableMessage, statusCode: 408);
    }
    // DNS / нет сети на устройстве
    if (raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('no address associated') ||
        raw.contains('name or service not known')) {
      return ApiException(noInternetMessage);
    }
    if (e is SocketException ||
        raw.contains('socketexception') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('clientexception') ||
        raw.contains('handshakeexception') ||
        raw.contains('connection errored')) {
      return ApiException(offlineMessage);
    }
    return ApiException(offlineMessage);
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = false,
    Duration timeout = const Duration(seconds: 25),
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

    try {
      late http.Response res;
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: headers, body: jsonEncode(cleanBody)).timeout(timeout);
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: jsonEncode(cleanBody)).timeout(timeout);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers).timeout(timeout);
          break;
        default:
          res = await http.get(uri, headers: headers).timeout(timeout);
      }
      if (res.statusCode == 401 && auth) {
        onUnauthorized?.call();
      }
      if (res.statusCode >= 400) {
        throw _fromResponse(res);
      }
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _fromNetwork(e);
    }
  }

  Future<Map<String, dynamic>> uploadListingImages(int listingId, List<String> filePaths) async {
    final uri = Uri.parse('$baseUrl/listings/$listingId/images');
    final req = http.MultipartRequest('POST', uri);
    final t = await token;
    if (t != null) req.headers['Authorization'] = 'Bearer $t';

    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) {
        throw ApiException('Файл фото не найден');
      }
      final size = await file.length();
      if (size > 6 * 1024 * 1024) {
        throw ApiException('Фото больше 6 МБ. Выберите другое или сожмите изображение');
      }
      final lower = path.toLowerCase();
      if (!(lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp'))) {
        throw ApiException('Допустимы только JPG, PNG или WEBP');
      }
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

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 401) {
        onUnauthorized?.call();
      }
      if (res.statusCode >= 400) {
        throw _fromResponse(res);
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _fromNetwork(e);
    }
  }

  Future<Map<String, dynamic>> uploadAvatar(String filePath) async {
    final uri = Uri.parse('$baseUrl/auth/me/avatar');
    final req = http.MultipartRequest('POST', uri);
    final t = await token;
    if (t != null) req.headers['Authorization'] = 'Bearer $t';
    final file = File(filePath);
    if (!await file.exists()) {
      throw ApiException('Файл фото не найден');
    }
    final size = await file.length();
    if (size > 6 * 1024 * 1024) {
      throw ApiException('Фото больше 6 МБ. Выберите другое или сожмите изображение');
    }
    final lower = filePath.toLowerCase();
    if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp'))) {
      throw ApiException('Допустимы только JPG, PNG или WEBP');
    }
    final type = lower.endsWith('.png')
        ? MediaType('image', 'png')
        : lower.endsWith('.webp')
            ? MediaType('image', 'webp')
            : MediaType('image', 'jpeg');
    req.files.add(await http.MultipartFile.fromPath('file', filePath, contentType: type));
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 401) {
        onUnauthorized?.call();
      }
      if (res.statusCode >= 400) {
        throw _fromResponse(res);
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _fromNetwork(e);
    }
  }
}
