import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  final List<XFile> photos = [];
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user;
    settlementId = user?['settlement_id'] as int?;
    phone.text = (user?['phone'] as String?) ?? '';
  }

  Future<void> _pickPhotos() async {
    final remaining = 5 - photos.length;
    if (remaining <= 0) return;
    final picked = await picker.pickMultiImage(imageQuality: 75, maxWidth: 1600);
    if (picked.isEmpty) return;
    setState(() {
      photos.addAll(picked.take(remaining));
    });
  }

  @override
  Widget build(BuildContext context) {
    final settlements = context.watch<AppState>().settlements;
    return Scaffold(
      appBar: AppBar(title: const Text('Новое объявление')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Фото (до 5)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...photos.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(e.value.path), width: 96, height: 96, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () => setState(() => photos.removeAt(e.key)),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (photos.length < 5)
                  InkWell(
                    onTap: _pickPhotos,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined),
                          SizedBox(height: 4),
                          Text('Добавить', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Цена (необязательно)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Телефон для связи', border: OutlineInputBorder()),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final titleText = title.text.trim();
                    final descText = description.text.trim();
                    if (titleText.length < 2) {
                      setState(() => error = 'Укажите заголовок');
                      return;
                    }
                    if (descText.length < 3) {
                      setState(() => error = 'Описание слишком короткое');
                      return;
                    }
                    if (settlementId == null) {
                      setState(() => error = 'Выберите населённый пункт');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await context.read<AppState>().createListing(
                        {
                          'title': titleText,
                          'description': descText,
                          'category': category,
                          'settlement_id': settlementId,
                          'price': price.text.trim().isEmpty ? null : double.tryParse(price.text.trim().replaceAll(',', '.')),
                          'contact_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                        },
                        imagePaths: photos.map((e) => e.path).toList(),
                      );
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
            child: Text(busy ? 'Публикация…' : 'Отправить на модерацию'),
          ),
        ],
      ),
    );
  }
}
