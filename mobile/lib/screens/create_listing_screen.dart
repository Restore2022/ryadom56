import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../listing_draft.dart';
import '../listing_templates.dart';
import '../responsive.dart';
import '../settlement_picker.dart';
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
  String? templateId;
  int? settlementId;
  bool isUrgent = false;
  int lifetimeDays = 30;
  String? error;
  bool busy = false;
  bool savedOnExit = false;
  bool restoredLocal = false;
  Timer? _localSaveTimer;
  int step = 0;
  final List<XFile> photos = [];
  final List<Map<String, dynamic>> existingImages = [];
  final picker = ImagePicker();

  static const maxPhotos = 5;

  int get totalPhotoCount => existingImages.length + photos.length;

  bool get _hidePhoneField {
    final p = (context.read<AppState>().user?['phone'] as String?)?.trim() ?? '';
    return p.isNotEmpty;
  }

  String? get _profilePhone {
    final p = (context.read<AppState>().user?['phone'] as String?)?.trim() ?? '';
    return p.isEmpty ? null : p;
  }

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
      isUrgent = initial['is_urgent'] == true;
      lifetimeDays = initial['lifetime_days'] == 60 ? 60 : 30;
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
    title.addListener(_scheduleLocalSave);
    description.addListener(_scheduleLocalSave);
    price.addListener(_scheduleLocalSave);
    phone.addListener(_scheduleLocalSave);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLocalDraft());
  }

  @override
  void dispose() {
    _localSaveTimer?.cancel();
    title.dispose();
    description.dispose();
    price.dispose();
    phone.dispose();
    super.dispose();
  }

  void _scheduleLocalSave() {
    _localSaveTimer?.cancel();
    _localSaveTimer = Timer(const Duration(milliseconds: 600), () {
      _persistLocal();
    });
  }

  ListingLocalDraft _snapshot() {
    return ListingLocalDraft(
      title: title.text,
      description: description.text,
      category: category,
      settlementId: settlementId,
      price: price.text,
      phone: phone.text,
      isUrgent: isUrgent,
      lifetimeDays: lifetimeDays,
      photoPaths: photos.map((e) => e.path).toList(),
    );
  }

  Future<void> _persistLocal() async {
    await ListingLocalDraft.save(widget.listingId, _snapshot());
  }

  Future<void> _restoreLocalDraft() async {
    final draft = await ListingLocalDraft.load(widget.listingId);
    if (draft == null || !mounted) return;
    setState(() {
      if (draft.title.isNotEmpty) title.text = draft.title;
      if (draft.description.isNotEmpty) description.text = draft.description;
      category = draft.category;
      if (draft.settlementId != null) settlementId = draft.settlementId;
      if (draft.price.isNotEmpty) price.text = draft.price;
      if (draft.phone.isNotEmpty) phone.text = draft.phone;
      isUrgent = draft.isUrgent;
      lifetimeDays = draft.lifetimeDays;
      final have = photos.map((e) => e.path).toSet();
      for (final path in draft.photoPaths) {
        if (!have.contains(path)) photos.add(XFile(path));
      }
      restoredLocal = true;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Вернули черновик: текст и фото, которые успели набрать')),
    );
  }

  void _applyTemplate(ListingTemplate t) {
    final titleLooksEmpty = title.text.trim().isEmpty || listingTemplates.any((x) => x.exampleTitle == title.text.trim());
    final descLooksEmpty =
        description.text.trim().isEmpty || listingTemplates.any((x) => x.exampleDescription == description.text.trim());
    setState(() {
      category = t.category;
      templateId = t.id;
      if (t.category == 'free') price.clear();
      if (titleLooksEmpty) title.text = t.exampleTitle;
      if (descLooksEmpty) description.text = t.exampleDescription;
    });
    _scheduleLocalSave();
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
      _scheduleLocalSave();
    } else {
      final remaining = maxPhotos - totalPhotoCount;
      if (remaining <= 0) return;
      final picked = await picker.pickMultiImage(imageQuality: 40, maxWidth: 1280);
      if (picked.isEmpty) return;
      setState(() => photos.addAll(picked.take(remaining)));
      _scheduleLocalSave();
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
    const titles = ['Фото', 'Что продаёте', 'Цена и село'];
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          if (!savedOnExit && !busy) await _autosaveDraft();
          return;
        }
        if (step > 0) setState(() { error = null; step -= 1; });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isEdit ? 'Редактировать' : 'Новое объявление'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Text('Шаг ${step + 1} из 3 · ${titles[step]}', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  SizedBox(
                    width: 88,
                    child: LinearProgressIndicator(value: (step + 1) / 3, minHeight: 6),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: ListView(
          padding: context.scrollPad(top: 16, bottom: 16),
          children: [
            if (step == 0) ..._photoStep(),
            if (step == 1) ..._whatStep(),
            if (step == 2) ..._placeStep(),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : _onPrimary,
              child: Text(
                busy
                    ? (widget.isEdit ? 'Сохранение…' : 'Публикация…')
                    : (step < 2 ? 'Далее' : (widget.isEdit ? 'Отправить на модерацию' : 'Отправить на модерацию')),
              ),
            ),
            if (step == 2) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy ? null : () => _submit(asDraft: true),
                child: const Text('Сохранить черновик'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onPrimary() {
    if (step == 0) {
      setState(() { error = null; step = 1; });
      return;
    }
    if (step == 1) {
      if (title.text.trim().length < 2) {
        setState(() => error = 'Укажите заголовок');
        return;
      }
      if (description.text.trim().length < 3) {
        setState(() => error = 'Описание слишком короткое');
        return;
      }
      setState(() { error = null; step = 2; });
      return;
    }
    _submit(asDraft: false);
  }

  List<Widget> _photoStep() {
    final state = context.watch<AppState>();
    return [
          Text(
            'Фото ($totalPhotoCount/$maxPhotos)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            widget.isEdit
                ? 'Можно без фото, но снимки лучше продают. Удалить, поменять порядок и добавить — до 5.'
                : 'Можно без фото и сразу далее. До 5 снимков — камера или галерея, лучше днём.',
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
    ];
  }

  List<Widget> _whatStep() {
    return [
          Text('Шаблоны', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Подставят заголовок и текст — потом поправьте под себя.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in listingTemplates)
                ChoiceChip(
                  label: Text(t.chipLabel),
                  selected: templateId == t.id,
                  onSelected: (_) => _applyTemplate(t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: title,
            decoration: InputDecoration(
              labelText: 'Заголовок',
              hintText: (templateById(templateId) ?? templateFor(category))?.titleHint ?? 'Кратко, что предлагаете',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: description,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Описание',
              hintText: (templateById(templateId) ?? templateFor(category))?.descriptionHint ?? 'Состояние, размер, где забрать',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Категория', border: OutlineInputBorder()),
            items: [
              for (final c in listingCategoryOrder)
                DropdownMenuItem(value: c, child: Text(listingCategoryLabels[c]!)),
            ],
            onChanged: (v) {
              setState(() {
                category = v ?? 'goods';
                templateId = null;
                if (category == 'free') price.clear();
              });
              _scheduleLocalSave();
            },
          ),
    ];
  }

  List<Widget> _placeStep() {
    final settlements = context.watch<AppState>().settlements;
    return [
          SettlementPicker(
            value: settlementId,
            settlements: settlements,
            onChanged: (v) {
              setState(() => settlementId = v);
              _scheduleLocalSave();
            },
          ),
          if (category != 'free') ...[
            const SizedBox(height: 12),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: category == 'wanted' ? 'До какой цены (необязательно)' : 'Цена (необязательно)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (!_hidePhoneField) ...[
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон для связи',
                hintText: '+79001234567',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: isUrgent,
            onChanged: (v) {
              setState(() => isUrgent = v);
              _scheduleLocalSave();
            },
            title: const Text('Срочно'),
            subtitle: const Text('Выделить объявление в ленте'),
          ),
          const SizedBox(height: 4),
          Text('Срок публикации', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Через это время объявление снимется само. Можно продлить в «Мои».',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30 дней')),
              ButtonSegment(value: 60, label: Text('60 дней')),
            ],
            selected: {lifetimeDays},
            onSelectionChanged: (v) {
              setState(() => lifetimeDays = v.first);
              _scheduleLocalSave();
            },
          ),
          if (widget.isEdit) ...[
            const SizedBox(height: 8),
            Text(
              'После отправки на модерацию объявление снова проверит администратор. Черновик можно дописать позже.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
    ];
  }

  bool get _hasContent {
    return title.text.trim().length >= 2 || description.text.trim().length >= 3 || photos.isNotEmpty || existingImages.isNotEmpty;
  }

  Future<void> _autosaveDraft() async {
    await _persistLocal();
    if (!_hasContent || settlementId == null) return;
    if (title.text.trim().length < 2 || description.text.trim().length < 3) return;
    try {
      final body = {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'category': category,
        'settlement_id': settlementId,
        'price': category == 'free' || price.text.trim().isEmpty
            ? null
            : double.tryParse(price.text.trim().replaceAll(',', '.')),
        'contact_phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'is_urgent': isUrgent,
        'lifetime_days': lifetimeDays,
      };
      final app = context.read<AppState>();
      if (widget.isEdit) {
        await app.updateListing(widget.listingId!, body, imagePaths: photos.map((e) => e.path).toList(), asDraft: true);
      } else {
        await app.createListing(body, imagePaths: photos.map((e) => e.path).toList(), asDraft: true);
      }
      savedOnExit = true;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Черновик сохранён автоматически')),
      );
    } catch (_) {}
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
    final phoneRaw = _hidePhoneField ? (_profilePhone ?? '') : phone.text.trim();
    if (phoneRaw.isNotEmpty) {
      final digits = phoneRaw.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 10) {
        setState(() => error = 'Укажите корректный телефон');
        return;
      }
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
      'price': category == 'free' || price.text.trim().isEmpty
          ? null
          : double.tryParse(price.text.trim().replaceAll(',', '.')),
      'contact_phone': phoneRaw.isEmpty ? null : phoneRaw,
      'is_urgent': isUrgent,
      'lifetime_days': lifetimeDays,
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
      savedOnExit = true;
      await ListingLocalDraft.clear(widget.listingId);
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
