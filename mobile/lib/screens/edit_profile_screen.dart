import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../settlement_picker.dart';
import '../state/app_state.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController password;
  late final TextEditingController currentPassword;
  int? settlementId;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user;
    name = TextEditingController(text: (user?['full_name'] as String?) ?? '');
    phone = TextEditingController(text: (user?['phone'] as String?) ?? '');
    password = TextEditingController();
    currentPassword = TextEditingController();
    settlementId = user?['settlement_id'] as int?;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    password.dispose();
    currentPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settlements = context.watch<AppState>().settlements;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Редактировать профиль')),
      body: ListView(
        padding: context.scrollPad(top: 16, bottom: 16),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Телефон', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SettlementPicker(
            value: settlementId,
            settlements: settlements,
            onChanged: (v) => setState(() => settlementId = v),
          ),
          const SizedBox(height: 24),
          Text('Смена пароля', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: currentPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Текущий пароль',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Новый пароль (необязательно)',
              border: OutlineInputBorder(),
            ),
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
                    final fullName = name.text.trim();
                    if (fullName.length < 2) {
                      setState(() => error = 'Укажите имя');
                      return;
                    }
                    if (settlementId == null) {
                      setState(() => error = 'Выберите населённый пункт');
                      return;
                    }
                    final newPass = password.text.trim();
                    if (newPass.isNotEmpty && newPass.length < 6) {
                      setState(() => error = 'Новый пароль — минимум 6 символов');
                      return;
                    }
                    if (newPass.isNotEmpty && currentPassword.text.isEmpty) {
                      setState(() => error = 'Введите текущий пароль');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await context.read<AppState>().updateProfile(
                        fullName: fullName,
                        phone: phone.text.trim(),
                        settlementId: settlementId,
                        password: newPass.isEmpty ? null : newPass,
                        currentPassword: newPass.isEmpty ? null : currentPassword.text,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Профиль сохранён')),
                        );
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      setState(() => error = AppState.userFriendlyError(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}
