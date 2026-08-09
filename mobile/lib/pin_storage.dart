import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный PIN (5 цифр) и резервный токен для быстрого входа.
class PinStorage {
  PinStorage._();

  static const _pinKey = 'ryadom_login_pin';
  static const _tokenKey = 'ryadom_pin_session_token';
  static const _flagKey = 'ryadom_pin_enabled';

  static const _storage = FlutterSecureStorage();

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_flagKey) == true) return true;
    final pin = await _storage.read(key: _pinKey);
    return pin != null && pin.length == 5;
  }

  static Future<void> setPin(String pin) async {
    assert(pin.length == 5 && RegExp(r'^\d{5}$').hasMatch(pin));
    await _storage.write(key: _pinKey, value: pin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flagKey, true);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    return stored != null && stored == pin;
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_flagKey);
  }

  static Future<void> saveSessionToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _tokenKey);
      return;
    }
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> readSessionToken() => _storage.read(key: _tokenKey);
}
