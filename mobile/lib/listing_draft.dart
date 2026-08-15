import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class ListingLocalDraft {
  ListingLocalDraft({
    this.title = '',
    this.description = '',
    this.category = 'goods',
    this.settlementId,
    this.price = '',
    this.phone = '',
    this.isUrgent = false,
    this.lifetimeDays = 30,
    this.photoPaths = const [],
  });

  String title;
  String description;
  String category;
  int? settlementId;
  String price;
  String phone;
  bool isUrgent;
  int lifetimeDays;
  List<String> photoPaths;

  bool get isEmpty =>
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      photoPaths.isEmpty &&
      price.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'category': category,
        'settlement_id': settlementId,
        'price': price,
        'phone': phone,
        'is_urgent': isUrgent,
        'lifetime_days': lifetimeDays,
        'photo_paths': photoPaths,
      };

  factory ListingLocalDraft.fromJson(Map<String, dynamic> json) {
    final rawPaths = (json['photo_paths'] as List?) ?? const [];
    final paths = rawPaths.map((e) => e.toString()).where((p) => p.isNotEmpty && File(p).existsSync()).toList();
    return ListingLocalDraft(
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'goods',
      settlementId: json['settlement_id'] as int?,
      price: (json['price'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      isUrgent: json['is_urgent'] == true,
      lifetimeDays: json['lifetime_days'] == 60 ? 60 : 30,
      photoPaths: paths,
    );
  }

  static String _key(int? listingId) => listingId == null ? 'listing_local_draft_new' : 'listing_local_draft_$listingId';

  static Future<ListingLocalDraft?> load(int? listingId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(listingId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final draft = ListingLocalDraft.fromJson(Map<String, dynamic>.from(map));
      return draft.isEmpty ? null : draft;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(int? listingId, ListingLocalDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft.isEmpty) {
      await prefs.remove(_key(listingId));
      return;
    }
    await prefs.setString(_key(listingId), jsonEncode(draft.toJson()));
  }

  static Future<void> clear(int? listingId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(listingId));
  }
}
