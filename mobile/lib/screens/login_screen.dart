import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui_helpers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      final msg = state.sessionMessage;
      if (msg != null) {
        setState(() => error = msg);
        state.clearSessionMessage();
      }
    });
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final mail = email.text.trim();
    final pass = password.text;
    if (!isValidEmail(mail)) {
      setState(() => error = 'Введите корректный email');
      return;
    }
    if (pass.isEmpty) {
      setState(() => error = 'Введите пароль');
      return;
    }
    if (pass.length < 6) {
      setState(() => error = 'Пароль не короче 6 символов');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<AppState>().login(mail, pass);
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e, context: 'login'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 36),
            Text('Рядом56', style: GoogleFonts.unbounded(fontSize: 34, fontWeight: FontWeight.w700, color: scheme.primary)),
            const SizedBox(height: 8),
            Text(
              'Объявления и справочник\nСакмарского района',
              style: GoogleFonts.manrope(fontSize: 18, height: 1.35, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 36),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              enabled: !busy,
              onSubmitted: (_) => busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Пароль',
                suffixIcon: IconButton(
                  onPressed: busy ? null : () => setState(() => obscure = !obscure),
                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: scheme.error, height: 1.35)),
              if (error == AppState.offlineMessage || error!.contains('не отвечает')) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : _submit,
                  child: const Text('Повторить'),
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : _submit,
              child: Text(busy ? 'Вход…' : 'Войти'),
            ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pushNamed(context, '/register'),
              child: const Text('Создать аккаунт'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    },
              child: const Text('Смотреть без входа'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Тема',
                onPressed: () {
                  final s = context.read<AppState>();
                  s.setDarkMode(!s.darkMode);
                },
                icon: Icon(context.watch<AppState>().darkMode ? Icons.light_mode : Icons.dark_mode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
