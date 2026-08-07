import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  bool booting = true;
  bool darkMode = false;
  Map<String, dynamic>? user;
  List<dynamic> settlements = [];
  List<dynamic> listings = [];
  int listingsTotal = 0;
  bool listingsHasMore = false;
  bool listingsLoadingMore = false;
  static const listingsPageSize = 20;
  List<dynamic> directory = [];
  List<dynamic> favorites = [];
  final Set<int> favoriteIds = {};
  String? error;
  bool listingsOffline = false;

  String? filterCategory;
  int? filterSettlementId;
  String filterQuery = '';
  String sort = 'newest';
  bool listingsLoading = false;

  String? directoryCategory;
  int? directorySettlementId;
  String directoryQuery = '';
  bool directoryLoading = false;

  static const offlineMessage =
      'Нет связи с сервером. Проверьте Wi‑Fi и что API запущен.';

  static String userFriendlyError(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('connection errored') ||
        lower.contains('xmlhttprequest error')) {
      return offlineMessage;
    }
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }

  bool get hasConnectionIssue =>
      listingsOffline || (error != null && error == offlineMessage);

  void _syncFavoriteIdsFromListings() {
    for (final item in listings) {
      if (item is Map && item['is_favorited'] == true && item['id'] is int) {
        favoriteIds.add(item['id'] as int);
      }
    }
  }

  void _applyFavoriteFlag(int id, bool favorited) {
    if (favorited) {
      favoriteIds.add(id);
    } else {
      favoriteIds.remove(id);
    }
    void patch(List<dynamic> list) {
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is Map && item['id'] == id) {
          list[i] = {...Map<String, dynamic>.from(item), 'is_favorited': favorited};
        }
      }
    }

    patch(listings);
    if (!favorited) {
      favorites.removeWhere((e) => e is Map && e['id'] == id);
    } else {
      patch(favorites);
    }
  }

  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      darkMode = prefs.getBool('dark_mode') ?? false;
      settlements = await api.request('/settlements') as List<dynamic>;
      final token = await api.token;
      if (token != null) {
        user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
        await reportDeviceInfo();
      }
      await Future.wait([loadListings(), loadDirectory()]);
      if (!listingsOffline) error = null;
    } catch (e) {
      error = userFriendlyError(e);
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _collectDevicePayload() async {
    final device = DeviceInfoPlugin();
    final package = await PackageInfo.fromPlatform();
    String? brand;
    String? model;
    String? os;
    final details = <String, String>{
      'platform': defaultTargetPlatform.name,
      'app_name': package.appName,
      'package': package.packageName,
      'build': package.buildNumber,
    };

    if (!kIsWeb && Platform.isAndroid) {
      final info = await device.androidInfo;
      brand = info.brand;
      model = info.model;
      os = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
      details.addAll({
        'manufacturer': info.manufacturer,
        'device': info.device,
        'product': info.product,
        'hardware': info.hardware,
        'is_physical': '${info.isPhysicalDevice}',
      });
    } else if (!kIsWeb && Platform.isIOS) {
      final info = await device.iosInfo;
      brand = 'Apple';
      model = info.utsname.machine;
      os = '${info.systemName} ${info.systemVersion}';
      details.addAll({
        'name': info.name,
        'model': info.model,
        'localized_model': info.localizedModel,
        'is_physical': '${info.isPhysicalDevice}',
      });
    } else {
      brand = defaultTargetPlatform.name;
      model = 'unknown';
      os = 'unknown';
    }

    return {
      'device_brand': brand,
      'device_model': model,
      'device_os': os,
      'app_version': '${package.version}+${package.buildNumber}',
      'device_info': details.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
    };
  }

  Future<void> reportDeviceInfo() async {
    if (user == null) return;
    try {
      final payload = await _collectDevicePayload();
      user = await api.request('/auth/device', method: 'POST', auth: true, body: payload) as Map<String, dynamic>;
    } catch (_) {
      // Не блокируем вход, если устройство не отправилось.
    }
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    notifyListeners();
  }

  Future<void> loadListings({bool append = false}) async {
    if (append) {
      if (!listingsHasMore || listingsLoadingMore || listingsLoading) return;
      listingsLoadingMore = true;
    } else {
      listingsLoading = true;
    }
    notifyListeners();
    try {
      final offset = append ? listings.length : 0;
      final params = <String, String>{
        'sort': sort,
        'limit': '$listingsPageSize',
        'offset': '$offset',
      };
      if (filterCategory != null) params['category'] = filterCategory!;
      if (filterSettlementId != null) params['settlement_id'] = '$filterSettlementId';
      if (filterQuery.trim().isNotEmpty) params['q'] = filterQuery.trim();
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final data = await api.request('/listings?$qs', auth: true);
      List<dynamic> items;
      int total;
      if (data is Map) {
        items = (data['items'] as List<dynamic>?) ?? [];
        total = (data['total'] as num?)?.toInt() ?? items.length;
      } else {
        items = data as List<dynamic>;
        total = items.length;
      }
      if (append) {
        listings = [...listings, ...items];
      } else {
        listings = items;
      }
      listingsTotal = total;
      listingsHasMore = listings.length < listingsTotal;
      _syncFavoriteIdsFromListings();
      listingsOffline = false;
      if (error == offlineMessage) error = null;
    } catch (e) {
      if (!append) {
        listingsOffline = true;
        error = userFriendlyError(e);
      }
    } finally {
      listingsLoading = false;
      listingsLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreListings() => loadListings(append: true);

  Future<void> loadDirectory() async {
    directoryLoading = true;
    notifyListeners();
    try {
      final params = <String, String>{};
      if (directoryCategory != null) params['category'] = directoryCategory!;
      if (directorySettlementId != null) params['settlement_id'] = '$directorySettlementId';
      if (directoryQuery.trim().isNotEmpty) params['q'] = directoryQuery.trim();
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final path = qs.isEmpty ? '/directory' : '/directory?$qs';
      directory = await api.request(path) as List<dynamic>;
    } finally {
      directoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> setDirectoryFilters({
    String? category,
    int? settlementId,
    String? query,
  }) async {
    directoryCategory = category;
    directorySettlementId = settlementId;
    if (query != null) directoryQuery = query;
    await loadDirectory();
  }

  Future<Map<String, dynamic>> getDirectoryItem(int id) async {
    return await api.request('/directory/$id') as Map<String, dynamic>;
  }

  Future<void> refreshPublic() async {
    await Future.wait([loadListings(), loadDirectory()]);
  }

  Future<void> applyListingFilters({
    String? category,
    int? settlementId,
    String? query,
    String? sortBy,
    bool clearCategory = false,
    bool clearSettlement = false,
  }) async {
    if (clearCategory) {
      filterCategory = null;
    } else if (category != null) {
      filterCategory = category.isEmpty ? null : category;
    }
    if (clearSettlement) {
      filterSettlementId = null;
    } else if (settlementId != null) {
      filterSettlementId = settlementId;
    }
    if (query != null) filterQuery = query;
    if (sortBy != null) sort = sortBy;
    await loadListings();
  }

  Future<void> setListingFilters({
    String? category,
    int? settlementId,
    String? query,
    String? sortBy,
  }) async {
    filterCategory = category;
    filterSettlementId = settlementId;
    if (query != null) filterQuery = query;
    if (sortBy != null) sort = sortBy;
    await loadListings();
  }

  Future<Map<String, dynamic>> getListing(int id) async {
    return await api.request('/listings/$id', auth: true) as Map<String, dynamic>;
  }

  Future<List<dynamic>> loadMyListings() async {
    final data = await api.request('/listings?mine=true&sort=newest&limit=100&offset=0', auth: true);
    if (data is Map) {
      return (data['items'] as List<dynamic>?) ?? [];
    }
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getLegalDoc(String slug) async {
    return await api.request('/legal/$slug') as Map<String, dynamic>;
  }

  Future<List<dynamic>> loadLegalDocs() async {
    return await api.request('/legal') as List<dynamic>;
  }

  Future<Map<String, dynamic>> deleteListingImage(int listingId, int imageId) async {
    final updated = await api.request('/listings/$listingId/images/$imageId', method: 'DELETE', auth: true)
        as Map<String, dynamic>;
    notifyListeners();
    return updated;
  }

  Future<Map<String, dynamic>> reorderListingImages(int listingId, List<int> imageIds) async {
    final updated = await api.request(
      '/listings/$listingId/images/reorder',
      method: 'PATCH',
      auth: true,
      body: {'image_ids': imageIds},
    ) as Map<String, dynamic>;
    notifyListeners();
    return updated;
  }

  Future<List<dynamic>> loadFavorites() async {
    favorites = await api.request('/listings/favorites', auth: true) as List<dynamic>;
    favoriteIds
      ..clear()
      ..addAll(
        favorites.whereType<Map>().where((e) => e['id'] is int).map((e) => e['id'] as int),
      );
    _syncFavoriteIdsFromListings();
    notifyListeners();
    return favorites;
  }

  Future<Map<String, dynamic>> toggleFavorite(int id, {bool? currentlyFavorited}) async {
    final was = currentlyFavorited ?? favoriteIds.contains(id) || _isFavoritedInLists(id);
    final updated = was
        ? await api.request('/listings/$id/favorite', method: 'DELETE', auth: true) as Map<String, dynamic>
        : await api.request('/listings/$id/favorite', method: 'POST', auth: true) as Map<String, dynamic>;
    final favorited = updated['is_favorited'] == true;
    _applyFavoriteFlag(id, favorited);
    if (favorited && !favorites.any((e) => e is Map && e['id'] == id)) {
      favorites.insert(0, updated);
    }
    notifyListeners();
    return updated;
  }

  bool _isFavoritedInLists(int id) {
    for (final item in listings) {
      if (item is Map && item['id'] == id) return item['is_favorited'] == true;
    }
    return false;
  }

  bool isFavorited(int id, {Map<String, dynamic>? item}) {
    if (favoriteIds.contains(id)) return true;
    if (item != null && item['is_favorited'] == true) return true;
    return _isFavoritedInLists(id);
  }

  Future<void> reportListing(int id, {required String reason, String? note}) async {
    await api.request(
      '/listings/$id/report',
      method: 'POST',
      auth: true,
      body: {'reason': reason, 'note': note},
    );
  }

  Future<Map<String, dynamic>> republishListing(int id) async {
    final updated = await api.request('/listings/$id/republish', method: 'POST', auth: true) as Map<String, dynamic>;
    await loadListings();
    notifyListeners();
    return updated;
  }

  Future<Map<String, dynamic>> updateListing(
    int id,
    Map<String, dynamic> body, {
    List<String> imagePaths = const [],
  }) async {
    var updated = await api.request('/listings/$id', method: 'PATCH', auth: true, body: body) as Map<String, dynamic>;
    if (imagePaths.isNotEmpty) {
      updated = await api.uploadListingImages(id, imagePaths);
    }
    await loadListings();
    notifyListeners();
    return updated;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? phone,
    int? settlementId,
    String? password,
    String? currentPassword,
  }) async {
    user = await api.request(
      '/auth/me',
      method: 'PATCH',
      auth: true,
      body: {
        'full_name': fullName,
        'phone': phone,
        'settlement_id': settlementId,
        'password': password,
        'current_password': currentPassword,
      },
    ) as Map<String, dynamic>;
    notifyListeners();
    return user!;
  }

  Future<Map<String, dynamic>> createListing(
    Map<String, dynamic> body, {
    List<String> imagePaths = const [],
  }) async {
    final created = await api.request('/listings', method: 'POST', auth: true, body: body) as Map<String, dynamic>;
    if (imagePaths.isNotEmpty) {
      final id = created['id'] as int;
      final withImages = await api.uploadListingImages(id, imagePaths);
      await loadListings();
      notifyListeners();
      return withImages;
    }
    await loadListings();
    notifyListeners();
    return created;
  }

  Future<Map<String, dynamic>> closeListing(int id, {required String reason, String? note}) async {
    final updated = await api.request(
      '/listings/$id/close',
      method: 'POST',
      auth: true,
      body: {'reason': reason, 'note': note},
    ) as Map<String, dynamic>;
    await loadListings();
    notifyListeners();
    return updated;
  }

  String mediaUrl(String? path) => api.resolveMedia(path);

  Future<void> login(String email, String password) async {
    final data = await api.request('/auth/login', method: 'POST', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    await api.setToken(data['access_token'] as String);
    user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
    await reportDeviceInfo();
    await refreshPublic();
    notifyListeners();
  }

  Future<void> register(Map<String, dynamic> body) async {
    final data = await api.request('/auth/register', method: 'POST', body: body) as Map<String, dynamic>;
    await api.setToken(data['access_token'] as String);
    user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
    await reportDeviceInfo();
    await refreshPublic();
    notifyListeners();
  }

  Future<void> logout() async {
    await api.setToken(null);
    user = null;
    favorites = [];
    favoriteIds.clear();
    await loadListings();
    notifyListeners();
  }
}
