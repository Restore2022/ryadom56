import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный PIN (5 цифр, SHA-256) и резервный токен для быстрого входа.
class PinStorage {
  PinStorage._();

  static const _hashKey = 'ryadom_login_pin_hash';
  static const _saltKey = 'ryadom_login_pin_salt';
  static const _tokenKey = 'ryadom_pin_session_token';
  static const _flagKey = 'ryadom_pin_enabled';
  static const _bioKey = 'ryadom_biometrics_enabled';

  static String _hash(String pin, String salt) {
    return sha256.convert(utf8.encode('ryadom56|$salt|$pin')).toString();
  }

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_flagKey) == true && prefs.getString(_hashKey) != null) {
      return true;
    }
    return false;
  }

  static Future<void> setPin(String pin) async {
    assert(pin.length == 5 && RegExp(r'^\d{5}$').hasMatch(pin));
    final prefs = await SharedPreferences.getInstance();
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(pin, salt));
    await prefs.setBool(_flagKey, true);
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    final expected = prefs.getString(_hashKey);
    if (salt == null || expected == null) return false;
    return _hash(pin, salt) == expected;
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_flagKey);
    await prefs.remove(_bioKey);
  }

  static Future<bool> biometricsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bioKey) == true;
  }

  static Future<void> setBiometricsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(_bioKey, true);
    } else {
      await prefs.remove(_bioKey);
    }
  }

  static Future<void> saveSessionToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tokenKey);
      return;
    }
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> readSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }
}
