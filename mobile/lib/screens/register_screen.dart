import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final phone = TextEditingController();
  int? settlementId;
  bool terms = false;
  bool privacy = false;
  bool listingRules = false;
  String? error;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final settlements = context.watch<AppState>().settlements;
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль (минимум 6)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Телефон (необязательно)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: settlementId,
            decoration: const InputDecoration(labelText: 'Населённый пункт', border: OutlineInputBorder()),
            items: settlements
                .map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['display_name'] as String, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => settlementId = v),
          ),
          CheckboxListTile(
            value: terms,
            onChanged: (v) => setState(() => terms = v ?? false),
            title: const Text('Принимаю пользовательское соглашение'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: privacy,
            onChanged: (v) => setState(() => privacy = v ?? false),
            title: const Text('Согласен с политикой конфиденциальности'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: listingRules,
            onChanged: (v) => setState(() => listingRules = v ?? false),
            title: const Text('Принимаю правила объявлений'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (settlementId == null) {
                      setState(() => error = 'Выберите населённый пункт');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await context.read<AppState>().register({
                        'full_name': name.text.trim(),
                        'email': email.text.trim(),
                        'password': password.text,
                        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                        'settlement_id': settlementId,
                        'accepted_terms': terms,
                        'accepted_privacy': privacy,
                        'accepted_listing_rules': listingRules,
                      });
                      if (context.mounted) Navigator.pushReplacementNamed(context, '/home');
                    } catch (e) {
                      setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Создание…' : 'Зарегистрироваться'),
          ),
        ],
      ),
    );
  }
}
