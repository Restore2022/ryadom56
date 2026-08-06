import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final title = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final phone = TextEditingController();
  String category = 'goods';
  int? settlementId;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user;
    settlementId = user?['settlement_id'] as int?;
  }

  @override
  Widget build(BuildContext context) {
    final settlements = context.watch<AppState>().settlements;
    return Scaffold(
      appBar: AppBar(title: const Text('Новое объявление')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Заголовок', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
            controller: description,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Описание', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Категория', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'goods', child: Text('Товары')),
              DropdownMenuItem(value: 'services', child: Text('Услуги')),
              DropdownMenuItem(value: 'jobs', child: Text('Работа')),
              DropdownMenuItem(value: 'rent', child: Text('Аренда')),
              DropdownMenuItem(value: 'free', child: Text('Отдам даром')),
              DropdownMenuItem(value: 'lost_found', child: Text('Потеряшки')),
            ],
            onChanged: (v) => setState(() => category = v ?? 'goods'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: settlementId,
            decoration: const InputDecoration(labelText: 'Населённый пункт', border: OutlineInputBorder()),
            items: settlements
                .map((s) => DropdownMenuItem<int>(value: s['id'] as int, child: Text(s['display_name'] as String)))
                .toList(),
            onChanged: (v) => setState(() => settlementId = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Цена (необязательно)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Телефон для связи', border: OutlineInputBorder())),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
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
                      await context.read<AppState>().createListing({
                        'title': title.text.trim(),
                        'description': description.text.trim(),
                        'category': category,
                        'settlement_id': settlementId,
                        'price': price.text.trim().isEmpty ? null : double.tryParse(price.text.trim().replaceAll(',', '.')),
                        'contact_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Отправлено на модерацию')),
                        );
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Отправка…' : 'Отправить на модерацию'),
          ),
        ],
      ),
    );
  }
}
