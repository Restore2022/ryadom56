import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final can = await _auth.canCheckBiometrics;
      if (!can) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'лицу';
      if (types.contains(BiometricType.fingerprint)) return 'отпечатку';
      if (types.contains(BiometricType.iris)) return 'радужке';
    } catch (_) {}
    return 'биометрии';
  }

  static Future<String> buttonLabel() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Войти по лицу';
      if (types.contains(BiometricType.fingerprint)) return 'Войти по отпечатку';
    } catch (_) {}
    return 'Войти по биометрии';
  }

  static Future<bool> authenticate({String reason = 'Подтвердите вход в Рядом56'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Рядом56',
            biometricHint: 'Коснитесь датчика',
            biometricNotRecognized: 'Не распознано, попробуйте ещё раз',
            biometricSuccess: 'Готово',
            cancelButton: 'Отмена',
            biometricRequiredTitle: 'Нужна биометрия',
            goToSettingsButton: 'Настройки',
            goToSettingsDescription: 'На этом телефоне не настроена биометрия.',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
