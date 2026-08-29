import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';

class ErrorReporter {
  ErrorReporter._();

  static ApiClient? api;
  static DateTime? _lastAt;
  static String? _lastMessage;

  static void attach(ApiClient client) {
    api = client;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      final msg = details.exceptionAsString();
      if (_ignore(msg)) return;
      unawaited(report(msg, details.stack?.toString(), screen: 'flutter'));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      final msg = error.toString();
      if (_ignore(msg)) return true;
      unawaited(report(msg, stack.toString(), screen: 'zone'));
      return true;
    };
  }

  static bool _ignore(String message) {
    final m = message.toLowerCase();
    if (m.contains('networkimageloadexception')) return true;
    if (m.contains('http request failed') && m.contains('/uploads/')) return true;
    if (m.contains('statuscode: 404') && m.contains('/uploads/')) return true;
    return false;
  }

  static Future<void> report(String message, String? stack, {String? screen}) async {
    final client = api;
    if (client == null) return;
    final now = DateTime.now();
    if (_lastMessage == message && _lastAt != null && now.difference(_lastAt!) < const Duration(seconds: 20)) {
      return;
    }
    _lastMessage = message;
    _lastAt = now;
    try {
      final info = await PackageInfo.fromPlatform();
      String? brand;
      String? model;
      String? os;
      try {
        if (Platform.isAndroid) {
          final d = await DeviceInfoPlugin().androidInfo;
          brand = d.brand;
          model = d.model;
          os = 'Android ${d.version.release}';
        }
      } catch (_) {}
      await client.request(
        '/client-errors',
        method: 'POST',
        auth: true,
        body: {
          'message': message.length > 500 ? message.substring(0, 500) : message,
          'stack': stack == null || stack.length <= 8000 ? stack : stack.substring(0, 8000),
          'screen': screen,
          'app_version': '${info.version}+${info.buildNumber}',
          'device_brand': brand,
          'device_model': model,
          'device_os': os,
        },
      );
    } catch (_) {}
  }
}
