import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key, this.listingId, this.initial});

  final int? listingId;
  final Map<String, dynamic>? initial;

  bool get isEdit => listingId != null;

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
  final List<Map<String, dynamic>> existingImages = [];
  final picker = ImagePicker();

  static const maxPhotos = 5;

  int get totalPhotoCount => existingImages.length + photos.length;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user;
    final initial = widget.initial;
    if (initial != null) {
      title.text = (initial['title'] as String?) ?? '';
      description.text = (initial['description'] as String?) ?? '';
      category = (initial['category'] as String?) ?? 'goods';
      settlementId = initial['settlement_id'] as int? ?? user?['settlement_id'] as int?;
      final p = initial['price'];
      if (p != null) price.text = '$p';
      phone.text = (initial['contact_phone'] as String?) ?? (user?['phone'] as String?) ?? '';
      final imgs = (initial['images'] as List?) ?? [];
      for (final img in imgs) {
        if (img is Map<String, dynamic>) {
          existingImages.add(Map<String, dynamic>.from(img));
        } else if (img is Map) {
          existingImages.add(Map<String, dynamic>.from(img));
        }
      }
      existingImages.sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0));
    } else {
      settlementId = user?['settlement_id'] as int?;
      phone.text = (user?['phone'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    price.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (totalPhotoCount >= maxPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Камера'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Галерея'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    if (source == ImageSource.camera) {
      final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 40, maxWidth: 1280);
      if (shot == null) return;
      setState(() => photos.add(shot));
    } else {
      final remaining = maxPhotos - totalPhotoCount;
      if (remaining <= 0) return;
      final picked = await picker.pickMultiImage(imageQuality: 40, maxWidth: 1280);
      if (picked.isEmpty) return;
      setState(() => photos.addAll(picked.take(remaining)));
    }
  }

  Future<void> _deleteExisting(int index) async {
    final img = existingImages[index];
    final id = img['id'] as int?;
    if (id == null || widget.listingId == null) return;
    setState(() => busy = true);
    try {
      final updated = await context.read<AppState>().deleteListingImage(widget.listingId!, id);
      final imgs = ((updated['images'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        existingImages
          ..clear()
          ..addAll(imgs);
        error = null;
      });
    } catch (e) {
      setState(() => error = AppState.userFriendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _moveExisting(int index, int delta) async {
    final next = index + delta;
    if (next < 0 || next >= existingImages.length || widget.listingId == null) return;
    setState(() {
      final item = existingImages.removeAt(index);
      existingImages.insert(next, item);
    });
    try {
      final ids = existingImages.map((e) => e['id'] as int).toList();
      final updated = await context.read<AppState>().reorderListingImages(widget.listingId!, ids);
      final imgs = ((updated['images'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted) {
        setState(() {
          existingImages
            ..clear()
            ..addAll(imgs);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = AppState.userFriendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settlements = context.watch<AppState>().settlements;
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Редактировать' : 'Новое объявление')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Фото ($totalPhotoCount/$maxPhotos)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            widget.isEdit
                ? 'Можно удалить, поменять порядок и добавить новые. До 5 фото, лучше днём при хорошем свете.'
                : 'До 5 фото — камера или галерея. Лучше снимать днём при хорошем свете.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...existingImages.asMap().entries.map((e) {
                  final url = state.mediaUrl(e.value['url'] as String?);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 96,
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    url,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 96,
                                      height: 96,
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      child: const Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: busy ? null : () => _deleteExisting(e.key),
                                    child: const CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.black54,
                                      child: Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: e.key == 0 || busy ? null : () => _moveExisting(e.key, -1),
                                icon: const Icon(Icons.chevron_left, size: 18),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: e.key >= existingImages.length - 1 || busy
                                    ? null
                                    : () => _moveExisting(e.key, 1),
                                icon: const Icon(Icons.chevron_right, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
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
                if (totalPhotoCount < maxPhotos)
                  InkWell(
                    onTap: busy ? null : _pickSource,
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
          if (widget.isEdit) ...[
            const SizedBox(height: 8),
            Text(
              'После отправки на модерацию объявление снова проверит администратор. Черновик можно дописать позже.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : () => _submit(asDraft: false),
            child: Text(
              busy
                  ? (widget.isEdit ? 'Сохранение…' : 'Публикация…')
                  : (widget.isEdit ? 'Отправить на модерацию' : 'Отправить на модерацию'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : () => _submit(asDraft: true),
            child: const Text('Сохранить черновик'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit({required bool asDraft}) async {
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
    final body = {
      'title': titleText,
      'description': descText,
      'category': category,
      'settlement_id': settlementId,
      'price': price.text.trim().isEmpty ? null : double.tryParse(price.text.trim().replaceAll(',', '.')),
      'contact_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
    };
    try {
      final app = context.read<AppState>();
      if (widget.isEdit) {
        await app.updateListing(
          widget.listingId!,
          body,
          imagePaths: photos.map((e) => e.path).toList(),
          asDraft: asDraft,
        );
      } else {
        await app.createListing(
          body,
          imagePaths: photos.map((e) => e.path).toList(),
          asDraft: asDraft,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              asDraft
                  ? 'Черновик сохранён'
                  : (widget.isEdit ? 'Изменения отправлены на модерацию' : 'Отправлено на модерацию'),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => error = AppState.userFriendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
