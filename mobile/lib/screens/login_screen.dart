import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(text: 'admin@ryadom56.ru');
  final password = TextEditingController(text: 'admin123');
  String? error;
  bool busy = false;

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
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль'),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await context.read<AppState>().login(email.text.trim(), password.text);
                        if (context.mounted) Navigator.pushReplacementNamed(context, '/home');
                      } catch (e) {
                        setState(() => error = e.toString());
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'Вход…' : 'Войти'),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/register'),
              child: const Text('Создать аккаунт'),
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
