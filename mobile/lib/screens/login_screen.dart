import 'package:flutter/material.dart';
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Text('Рядом56', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Сакмарский район и Оренбург — объявления и справочник'),
            const SizedBox(height: 32),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль', border: OutlineInputBorder()),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
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
          ],
        ),
      ),
    );
  }
}
