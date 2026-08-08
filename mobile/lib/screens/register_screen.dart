import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui_helpers.dart';
import 'home_shell.dart';
import 'legal_doc_screen.dart';

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

  void _openLegal(String slug, String title) {
    Navigator.push(context, fastRoute(LegalDocScreen(slug: slug, title: title)));
  }

  Future<void> _register() async {
    final fullName = name.text.trim();
    final mail = email.text.trim();
    if (fullName.length < 2) {
      setState(() => error = 'Укажите имя');
      return;
    }
    if (!isValidEmail(mail)) {
      setState(() => error = 'Введите корректный email');
      return;
    }
    if (password.text.length < 6) {
      setState(() => error = 'Пароль не короче 6 символов');
      return;
    }
    if (settlementId == null) {
      setState(() => error = 'Выберите населённый пункт');
      return;
    }
    if (!terms || !privacy || !listingRules) {
      setState(() => error = 'Нужно принять все соглашения');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<AppState>().register({
        'full_name': fullName,
        'email': mail,
        'password': password.text,
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'settlement_id': settlementId,
        'accepted_terms': terms,
        'accepted_privacy': privacy,
        'accepted_listing_rules': listingRules,
      });
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e, context: 'register'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _legalCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String prefix,
    required String linkLabel,
    required String slug,
    required String title,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$prefix ', style: TextStyle(color: scheme.onSurface, fontSize: 14, height: 1.35)),
          GestureDetector(
            onTap: () => _openLegal(slug, title),
            child: Text(
              linkLabel,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
          _legalCheckbox(
            value: terms,
            onChanged: (v) => setState(() => terms = v ?? false),
            prefix: 'Принимаю',
            linkLabel: 'пользовательское соглашение',
            slug: 'terms',
            title: 'Пользовательское соглашение',
          ),
          _legalCheckbox(
            value: privacy,
            onChanged: (v) => setState(() => privacy = v ?? false),
            prefix: 'Согласен с',
            linkLabel: 'политикой конфиденциальности',
            slug: 'privacy',
            title: 'Политика конфиденциальности',
          ),
          _legalCheckbox(
            value: listingRules,
            onChanged: (v) => setState(() => listingRules = v ?? false),
            prefix: 'Принимаю',
            linkLabel: 'правила объявлений',
            slug: 'listing_rules',
            title: 'Правила размещения объявлений',
          ),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          if (error != null && (error == AppState.offlineMessage || error!.contains('не отвечает')))
            OutlinedButton(
              onPressed: busy ? null : () => _register(),
              child: const Text('Повторить'),
            ),
          FilledButton(
            onPressed: busy ? null : _register,
            child: Text(busy ? 'Создание…' : 'Зарегистрироваться'),
          ),
        ],
      ),
    );
  }
}
