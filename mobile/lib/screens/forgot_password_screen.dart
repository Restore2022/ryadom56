import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state/app_state.dart';
import '../ui_helpers.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final email = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  int step = 0;
  bool busy = false;
  bool obscure = true;
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    email.text = widget.initialEmail?.trim() ?? '';
  }

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final mail = email.text.trim();
    if (!isValidEmail(mail)) {
      setState(() => error = 'Введите корректный email');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final data = await context.read<AppState>().requestPasswordReset(mail);
      if (!mounted) return;
      setState(() {
        step = 1;
        info = data;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submitNewPassword() async {
    final mail = email.text.trim();
    final rawCode = code.text.trim();
    final pass = password.text;
    if (rawCode.length != 6) {
      setState(() => error = 'Введите 6-значный код из письма');
      return;
    }
    if (pass.length < 6) {
      setState(() => error = 'Пароль не короче 6 символов');
      return;
    }
    if (pass != confirm.text) {
      setState(() => error = 'Пароли не совпадают');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<AppState>().confirmPasswordReset(
            email: mail,
            code: rawCode,
            password: pass,
          );
      if (!mounted) return;
      showAppSnack(context, 'Пароль обновлён. Войдите с новым паролем');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Восстановление пароля')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            step == 0 ? 'Укажите email аккаунта' : 'Код из письма',
            style: GoogleFonts.unbounded(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            step == 0
                ? 'Отправим 6-значный код на почту. Если такого адреса нет в системе, письмо не придёт.'
                : 'Введите код и задайте новый пароль. Код действует 20 минут.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            enabled: !busy && step == 0,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          ),
          if (step == 1) ...[
            const SizedBox(height: 12),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              enabled: !busy,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Код из письма',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: obscure,
              enabled: !busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Новый пароль',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: busy ? null : () => setState(() => obscure = !obscure),
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: obscure,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Повторите пароль', border: OutlineInputBorder()),
            ),
          ],
          if (info != null) ...[
            const SizedBox(height: 12),
            Text(info!, style: TextStyle(color: scheme.primary, height: 1.35)),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: scheme.error, height: 1.35)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : (step == 0 ? _sendCode : _submitNewPassword),
            child: Text(busy ? 'Отправка…' : (step == 0 ? 'Отправить код' : 'Сохранить пароль')),
          ),
          if (step == 1)
            TextButton(
              onPressed: busy ? null : _sendCode,
              child: const Text('Отправить код ещё раз'),
            ),
          if (error != null &&
              (error == AppState.offlineMessage ||
                  error == ApiClient.noInternetMessage ||
                  error == ApiClient.serverUnreachableMessage ||
                  error!.contains('связи') ||
                  error!.contains('интернет')))
            OutlinedButton(
              onPressed: busy ? null : (step == 0 ? _sendCode : _submitNewPassword),
              child: const Text('Повторить'),
            ),
        ],
      ),
    );
  }
}
