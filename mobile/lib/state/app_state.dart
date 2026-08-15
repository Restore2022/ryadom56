import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../biometric_service.dart';
import '../pin_storage.dart';
import '../push_service.dart';

({List<dynamic> items, int total}) parsePage(dynamic data) {
  if (data is Map) {
    final items = (data['items'] as List<dynamic>?) ?? [];
    final total = (data['total'] as num?)?.toInt() ?? items.length;
    return (items: items, total: total);
  }
  final items = data is List ? List<dynamic>.from(data) : <dynamic>[];
  return (items: items, total: items.length);
}

class AppState extends ChangeNotifier {
  AppState(this.api) {
    api.onUnauthorized = _handleUnauthorized;
  }

  final ApiClient api;
  bool booting = true;
  bool darkMode = false;
  bool hasPin = false;
  bool pinUnlocked = false;
  bool biometricsEnabled = false;
  bool biometricsAvailable = false;
  String biometricsLabel = 'биометрии';
  Map<String, dynamic>? user;
  List<dynamic> settlements = [];
  List<dynamic> listings = [];
  int listingsTotal = 0;
  bool listingsHasMore = false;
  bool listingsLoadingMore = false;
  static const listingsPageSize = 20;
  List<dynamic> directory = [];
  int directoryTotal = 0;
  bool directoryHasMore = false;
  bool directoryLoadingMore = false;
  static const directoryPageSize = 30;
  List<dynamic> favorites = [];
  final Set<int> favoriteIds = {};
  final Set<int> directoryFavoriteIds = {};
  final Set<int> transportFavoriteIds = {};
  List<Map<String, dynamic>> viewHistory = [];
  String? error;
  bool listingsOffline = false;
  bool directoryOffline = false;
  bool lastNewsFromCache = false;
  bool lastTransportFromCache = false;
  String? sessionMessage;
  bool _clearingSession = false;

  String? filterCategory;
  int? filterSettlementId;
  String filterQuery = '';
  String sort = 'newest';
  double? nearLat;
  double? nearLon;
  bool filterHasPhotos = false;
  double? filterPriceMin;
  double? filterPriceMax;
  bool listingsLoading = false;
  int unreadNotifications = 0;
  int? preferredSettlementId;
  bool onboardingDone = false;

  String? directoryCategory;
  int? directorySettlementId;
  String directoryQuery = '';
  String directorySort = 'title';
  double? directoryNearLat;
  double? directoryNearLon;
  bool directoryLoading = false;

  static const offlineMessage = ApiClient.offlineMessage;

  static String userFriendlyError(Object e) {
    if (e is ApiException) {
      // на всякий случай прячем старые технические формулировки
      final m = e.message;
      final lower = m.toLowerCase();
      if (lower.contains('api') || lower.contains('wi-fi') || lower.contains('wi‑fi') || lower.contains('wifi')) {
        return ApiClient.offlineMessage;
      }
      return m;
    }
    final raw = e.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('no address associated') ||
        lower.contains('name or service not known')) {
      return ApiClient.noInternetMessage;
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return ApiClient.serverUnreachableMessage;
    }
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('connection errored') ||
        lower.contains('xmlhttprequest error')) {
      return offlineMessage;
    }
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    if (raw.startsWith('ApiException: ')) {
      return raw.substring('ApiException: '.length);
    }
    // Не показываем сырой стек/английский технический текст
    if (lower.contains('api') || RegExp(r'[a-z]{4,}exception').hasMatch(lower)) {
      return offlineMessage;
    }
    return raw;
  }

  bool get hasConnectionIssue {
    if (listingsOffline || directoryOffline) return true;
    final err = error;
    if (err == null) return false;
    return err == offlineMessage ||
        err == ApiClient.noInternetMessage ||
        err == ApiClient.serverUnreachableMessage;
  }

  Future<void> _handleUnauthorized() async {
    if (_clearingSession || user == null) return;
    _clearingSession = true;
    try {
      await api.setToken(null);
      await PinStorage.saveSessionToken(null);
      _hasPinSession = false;
      user = null;
      favorites = [];
      favoriteIds.clear();
      directoryFavoriteIds.clear();
      transportFavoriteIds.clear();
      unreadNotifications = 0;
      unreadChats = 0;
      sessionMessage = 'Сессия истекла. Войдите снова';
      notifyListeners();
    } finally {
      _clearingSession = false;
    }
  }

  void clearSessionMessage() {
    sessionMessage = null;
  }

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

  static const _filtersKey = 'listing_filters';
  static const _onboardingKey = 'onboarding_done';
  static const _settlementPrefKey = 'preferred_settlement_id';
  static const _newsCachePrefix = 'cache_news_json';
  static const _transportCachePrefix = 'cache_transport_';

  /// Вошедший пользователь обязан задать PIN (защита от посторонних на телефоне).
  bool get needsPinSetup => user != null && !hasPin;

  /// Блокируем приложение PIN, если сессия есть, а код ещё не введён.
  bool get needsPinUnlock => hasPin && !pinUnlocked && user != null;

  bool get canUnlockWithPin => hasPin && _hasPinSession;

  bool _hasPinSession = false;

  void markPinUnlocked() {
    pinUnlocked = true;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      darkMode = prefs.getBool('dark_mode') ?? false;
      onboardingDone = prefs.getBool(_onboardingKey) ?? false;
      preferredSettlementId = prefs.getInt(_settlementPrefKey);
      hasPin = await PinStorage.hasPin();
      _hasPinSession = (await PinStorage.readSessionToken()) != null;
      await refreshBiometricsState();
      await _loadSavedFilters(prefs);
      await _loadViewHistory(prefs);
      try {
        settlements = await api.request('/settlements') as List<dynamic>;
      } catch (e) {
        error = userFriendlyError(e);
      }
      final token = await api.token;
      if (token != null) {
        try {
          user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
          await reportDeviceInfo();
          await PinStorage.saveSessionToken(token);
          _hasPinSession = true;
          // Если PIN задан — на холодном старте просим его снова.
          pinUnlocked = !hasPin;
        } on ApiException catch (e) {
          if (e.statusCode == 401 || e.statusCode == 403) {
            await api.setToken(null);
            user = null;
            sessionMessage = 'Сессия истекла. Войдите снова';
            pinUnlocked = false;
          }
        } catch (_) {
          await api.setToken(null);
          user = null;
          pinUnlocked = false;
        }
      } else if (hasPin && _hasPinSession) {
        // Токен сброшен, но PIN + резервная сессия есть — можно войти по PIN.
        pinUnlocked = false;
      } else {
        pinUnlocked = true;
      }
      await Future.wait([loadListings(), loadDirectory()]);
      if (user != null && pinUnlocked) await refreshUnreadNotifications();
      if (!listingsOffline && !directoryOffline) error = null;
    } catch (e) {
      error = userFriendlyError(e);
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> refreshBiometricsState() async {
    biometricsAvailable = await BiometricService.isAvailable();
    biometricsEnabled = await PinStorage.biometricsEnabled();
    if (biometricsAvailable) {
      biometricsLabel = await BiometricService.label();
    } else {
      biometricsLabel = 'биометрии';
    }
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await PinStorage.setBiometricsEnabled(enabled);
    biometricsEnabled = enabled;
    notifyListeners();
  }

  Future<void> verifyAccountPassword(String password) async {
    var token = await api.token;
    token ??= await PinStorage.readSessionToken();
    if (token != null && token.isNotEmpty) {
      await api.setToken(token);
    }
    await api.request('/auth/verify-password', method: 'POST', auth: true, body: {
      'password': password,
    });
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await PinStorage.verifyPin(pin);
    if (!ok) return false;
    return _restoreSessionAfterLocalUnlock();
  }

  Future<bool> unlockWithBiometrics() async {
    if (!await PinStorage.biometricsEnabled()) return false;
    final ok = await BiometricService.authenticate();
    if (!ok) return false;
    return _restoreSessionAfterLocalUnlock();
  }

  Future<bool> _restoreSessionAfterLocalUnlock() async {
    var token = await api.token;
    token ??= await PinStorage.readSessionToken();
    if (token == null || token.isEmpty) {
      pinUnlocked = false;
      notifyListeners();
      return false;
    }
    await api.setToken(token);
    try {
      user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
      await PinStorage.saveSessionToken(token);
      _hasPinSession = true;
      await reportDeviceInfo();
      await refreshPublic();
      await refreshUnreadNotifications();
      pinUnlocked = true;
      hasPin = true;
      notifyListeners();
      return true;
    } catch (_) {
      await api.setToken(null);
      await PinStorage.saveSessionToken(null);
      _hasPinSession = false;
      user = null;
      pinUnlocked = false;
      notifyListeners();
      return false;
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
      'device_id': await _ensureDeviceId(),
      'device_brand': brand,
      'device_model': model,
      'device_os': os,
      'app_version': '${package.version}+${package.buildNumber}',
      'device_info': details.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      if ((await PushService.instance.ensureToken()) != null)
        'fcm_token': PushService.instance.token,
    };
  }

  Future<void> reportDeviceInfo() async {
    if (user == null) return;
    try {
      await PushService.instance.ensureToken();
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
      if (filterHasPhotos) params['has_photos'] = 'true';
      if (filterPriceMin != null) params['price_min'] = '${filterPriceMin!}';
      if (filterPriceMax != null) params['price_max'] = '${filterPriceMax!}';
      if (sort == 'near') {
        if (nearLat != null && nearLon != null) {
          params['lat'] = '$nearLat';
          params['lon'] = '$nearLon';
        }
      }
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final data = await api.request('/listings?$qs', auth: true);
      final page = parsePage(data);
      final items = page.items;
      final total = page.total;
      if (append) {
        listings = [...listings, ...items];
      } else {
        listings = items;
      }
      listingsTotal = total;
      listingsHasMore = listings.length < listingsTotal;
      _syncFavoriteIdsFromListings();
      listingsOffline = false;
      if (error == offlineMessage ||
          error == ApiClient.noInternetMessage ||
          error == ApiClient.serverUnreachableMessage) {
        error = null;
      }
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

  Future<void> loadDirectory({bool append = false}) async {
    if (append) {
      if (!directoryHasMore || directoryLoadingMore || directoryLoading) return;
      directoryLoadingMore = true;
    } else {
      directoryLoading = true;
    }
    notifyListeners();
    try {
      final offset = append ? directory.length : 0;
      final params = <String, String>{
        'limit': '$directoryPageSize',
        'offset': '$offset',
        'sort': directorySort,
      };
      if (directoryCategory != null) params['category'] = directoryCategory!;
      if (directorySettlementId != null) params['settlement_id'] = '$directorySettlementId';
      if (directoryQuery.trim().isNotEmpty) params['q'] = directoryQuery.trim();
      if (directorySort == 'near' && directoryNearLat != null && directoryNearLon != null) {
        params['lat'] = '$directoryNearLat';
        params['lon'] = '$directoryNearLon';
      }
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final data = await api.request('/directory?$qs', auth: true);
      final page = parsePage(data);
      final items = page.items;
      final total = page.total;
      if (append) {
        directory = [...directory, ...items];
      } else {
        directory = items;
      }
      directoryTotal = total;
      directoryHasMore = directory.length < directoryTotal;
      for (final item in items) {
        if (item is Map && item['is_favorited'] == true && item['id'] is int) {
          directoryFavoriteIds.add(item['id'] as int);
        }
      }
      directoryOffline = false;
      if (!listingsOffline &&
          (error == offlineMessage ||
              error == ApiClient.noInternetMessage ||
              error == ApiClient.serverUnreachableMessage)) {
        error = null;
      }
    } catch (e) {
      if (!append) {
        directoryOffline = true;
        error = userFriendlyError(e);
      }
    } finally {
      directoryLoading = false;
      directoryLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreDirectory() => loadDirectory(append: true);

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

  Future<({List<dynamic> items, int total})> loadNews({
    int? settlementId,
    bool useCacheOnError = true,
    int offset = 0,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (settlementId != null) params['settlement_id'] = '$settlementId';
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final path = '/news?$qs';
    try {
      final data = await api.request(path);
      final page = parsePage(data);
      if (offset == 0) await _saveNewsCache(settlementId, page.items);
      lastNewsFromCache = false;
      notifyListeners();
      return page;
    } catch (e) {
      if (!useCacheOnError) rethrow;
      final cached = await _loadNewsCache(settlementId);
      if (cached != null) {
        lastNewsFromCache = true;
        notifyListeners();
        return (items: cached, total: cached.length);
      }
      lastNewsFromCache = false;
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loadActiveAlert() async {
    final data = await api.request('/alerts/active');
    if (data == null) return null;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> loadActiveAlerts({int limit = 5}) async {
    try {
      final data = await api.request('/alerts/active/list?limit=$limit');
      if (data is List) {
        return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    final single = await loadActiveAlert();
    if (single != null) return [single];
    return [];
  }

  Future<({List<dynamic> items, int total})> loadEvents({
    bool? upcoming,
    String? q,
    int? settlementId,
    int offset = 0,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (upcoming != null) params['upcoming'] = upcoming ? '1' : '0';
    if (settlementId != null) params['settlement_id'] = '$settlementId';
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final data = await api.request('/events?$qs');
    return parsePage(data);
  }

  Future<Map<String, dynamic>> getEvent(int id) async {
    return await api.request('/events/$id') as Map<String, dynamic>;
  }

  Future<void> trackEventView(int id) async {
    try {
      await api.request('/events/$id/view', method: 'POST');
    } catch (_) {}
  }

  void _syncTransportFavoriteIds(List<dynamic> rows) {
    for (final item in rows) {
      if (item is Map && item['is_favorited'] == true && item['id'] is int) {
        transportFavoriteIds.add(item['id'] as int);
      }
    }
  }

  Future<({List<dynamic> items, int total})> loadTransport({
    String? q,
    int? settlementId,
    String? day,
    bool favoritesOnly = false,
    bool useCacheOnError = true,
    int offset = 0,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (settlementId != null) params['settlement_id'] = '$settlementId';
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (day != null && day.isNotEmpty) params['day'] = day;
    if (favoritesOnly) params['favorites_only'] = 'true';
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final path = '/transport?$qs';
    try {
      final data = await api.request(path, auth: true);
      final page = parsePage(data);
      _syncTransportFavoriteIds(page.items);
      if (offset == 0 && settlementId != null) {
        await _saveTransportCache(settlementId, day ?? 'today', favoritesOnly, page.items);
      }
      lastTransportFromCache = false;
      notifyListeners();
      return page;
    } catch (e) {
      if (!useCacheOnError || settlementId == null) rethrow;
      final cached = await _loadTransportCache(settlementId, day ?? 'today', favoritesOnly);
      if (cached != null) {
        _syncTransportFavoriteIds(cached);
        lastTransportFromCache = true;
        notifyListeners();
        return (items: cached, total: cached.length);
      }
      lastTransportFromCache = false;
      rethrow;
    }
  }

  Future<void> reportTransportOutdated(int routeId) async {
    await api.request('/transport/$routeId/outdated', method: 'POST', auth: true);
  }

  Future<Map<String, dynamic>> getTransportRoute(int id) async {
    final item = await api.request('/transport/$id', auth: true) as Map<String, dynamic>;
    if (item['is_favorited'] == true) {
      transportFavoriteIds.add(id);
    } else {
      transportFavoriteIds.remove(id);
    }
    notifyListeners();
    return item;
  }

  Future<void> trackTransportView(int id) async {
    try {
      await api.request('/transport/$id/view', method: 'POST', auth: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> toggleTransportFavorite(int routeId, {bool? currentlyFavorited}) async {
    final was = currentlyFavorited ?? transportFavoriteIds.contains(routeId);
    final updated = was
        ? await api.request('/transport/$routeId/favorite', method: 'DELETE', auth: true) as Map<String, dynamic>
        : await api.request('/transport/$routeId/favorite', method: 'POST', auth: true) as Map<String, dynamic>;
    final favorited = updated['is_favorited'] == true;
    if (favorited) {
      transportFavoriteIds.add(routeId);
    } else {
      transportFavoriteIds.remove(routeId);
    }
    notifyListeners();
    return updated;
  }

  bool isTransportFavorited(int id, {Map<String, dynamic>? item}) {
    if (transportFavoriteIds.contains(id)) return true;
    if (item != null && item['is_favorited'] == true) return true;
    return false;
  }

  Future<void> refreshPublic() async {
    await Future.wait([loadListings(), loadDirectory()]);
  }

  Future<void> applyListingFilters({
    String? category,
    int? settlementId,
    String? query,
    String? sortBy,
    bool? hasPhotos,
    double? priceMin,
    double? priceMax,
    bool clearCategory = false,
    bool clearSettlement = false,
    bool clearPriceMin = false,
    bool clearPriceMax = false,
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
    if (sortBy != null) {
      sort = sortBy;
      if (sortBy != 'near') {
        nearLat = null;
        nearLon = null;
      }
    }
    if (hasPhotos != null) filterHasPhotos = hasPhotos;
    if (clearPriceMin) {
      filterPriceMin = null;
    } else if (priceMin != null) {
      filterPriceMin = priceMin;
    }
    if (clearPriceMax) {
      filterPriceMax = null;
    } else if (priceMax != null) {
      filterPriceMax = priceMax;
    }
    await _persistFilters();
    await loadListings();
  }

  Future<void> setNearOrigin({double? lat, double? lon, bool enabled = true}) async {
    if (enabled) {
      sort = 'near';
      nearLat = lat;
      nearLon = lon;
    } else if (sort == 'near') {
      sort = 'newest';
      nearLat = null;
      nearLon = null;
    }
    await _persistFilters();
    await loadListings();
  }

  Future<void> setDirectoryNear({double? lat, double? lon, bool enabled = true}) async {
    if (enabled) {
      directorySort = 'near';
      directoryNearLat = lat;
      directoryNearLon = lon;
    } else {
      directorySort = 'title';
      directoryNearLat = null;
      directoryNearLon = null;
    }
    await loadDirectory();
  }

  Future<void> setListingFilters({
    String? category,
    int? settlementId,
    String? query,
    String? sortBy,
    bool? hasPhotos,
    double? priceMin,
    double? priceMax,
  }) async {
    filterCategory = category;
    filterSettlementId = settlementId;
    if (query != null) filterQuery = query;
    if (sortBy != null) sort = sortBy;
    if (hasPhotos != null) filterHasPhotos = hasPhotos;
    filterPriceMin = priceMin;
    filterPriceMax = priceMax;
    await _persistFilters();
    await loadListings();
  }

  Future<void> _loadSavedFilters(SharedPreferences prefs) async {
    final raw = prefs.getString(_filtersKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      filterCategory = map['category'] as String?;
      filterSettlementId = (map['settlement_id'] as num?)?.toInt();
      filterQuery = map['query'] as String? ?? '';
      sort = map['sort'] as String? ?? 'newest';
      if (sort == 'near' && filterSettlementId == null) {
        sort = 'newest';
      }
      filterHasPhotos = map['has_photos'] == true;
      filterPriceMin = (map['price_min'] as num?)?.toDouble();
      filterPriceMax = (map['price_max'] as num?)?.toDouble();
    } catch (_) {}
  }

  Future<void> _persistFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _filtersKey,
      jsonEncode({
        'category': filterCategory,
        'settlement_id': filterSettlementId,
        'query': filterQuery,
        'sort': sort,
        'has_photos': filterHasPhotos,
        'price_min': filterPriceMin,
        'price_max': filterPriceMax,
      }),
    );
  }

  Future<void> setPreferredSettlement(int? settlementId) async {
    preferredSettlementId = settlementId;
    final prefs = await SharedPreferences.getInstance();
    if (settlementId == null) {
      await prefs.remove(_settlementPrefKey);
    } else {
      await prefs.setInt(_settlementPrefKey, settlementId);
    }
    notifyListeners();
  }

  Future<void> completeOnboarding({int? settlementId}) async {
    onboardingDone = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    if (settlementId != null) await setPreferredSettlement(settlementId);
    notifyListeners();
  }

  Future<Map<String, dynamic>> getPublicProfile(int userId) async {
    return await api.request('/auth/users/$userId/public') as Map<String, dynamic>;
  }

  int unreadChats = 0;

  Future<List<dynamic>> loadListingMessages(int listingId, {int? peerId}) async {
    final qs = peerId != null ? '?peer_id=$peerId' : '';
    return await api.request('/listings/$listingId/messages$qs', auth: true) as List<dynamic>;
  }

  Future<Map<String, dynamic>> sendListingMessage(int listingId, String body, {int? peerId}) async {
    return await api.request(
      '/listings/$listingId/messages',
      method: 'POST',
      auth: true,
      body: {
        'body': body,
        if (peerId != null) 'peer_id': peerId,
      },
    ) as Map<String, dynamic>;
  }

  Future<List<dynamic>> loadConversations() async {
    final rows = await api.request('/listings/conversations', auth: true) as List<dynamic>;
    var unread = 0;
    for (final row in rows) {
      if (row is Map && row['unread_count'] is int) {
        unread += row['unread_count'] as int;
      }
    }
    unreadChats = unread;
    notifyListeners();
    return rows;
  }

  Future<void> refreshUnreadChats() async {
    if (user == null) {
      unreadChats = 0;
      notifyListeners();
      return;
    }
    try {
      await loadConversations();
    } catch (_) {}
  }

  Future<List<dynamic>> loadReportsAgainstMe() async {
    return await api.request('/listings/reports/against-me', auth: true) as List<dynamic>;
  }

  String _newsCacheStorageKey(int? settlementId) => '${_newsCachePrefix}_$settlementId';

  Future<void> _saveNewsCache(int? settlementId, List<dynamic> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _newsCacheStorageKey(settlementId),
      jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'items': rows}),
    );
  }

  Future<List<dynamic>?> _loadNewsCache(int? settlementId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_newsCacheStorageKey(settlementId));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (map['items'] as List<dynamic>?) ?? [];
    } catch (_) {
      return null;
    }
  }

  String _transportCacheKey(int settlementId, String day, bool favoritesOnly) =>
      '$_transportCachePrefix${settlementId}_${day}_${favoritesOnly ? 1 : 0}';

  Future<void> _saveTransportCache(int settlementId, String day, bool favoritesOnly, List<dynamic> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _transportCacheKey(settlementId, day, favoritesOnly),
      jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'items': rows}),
    );
  }

  Future<List<dynamic>?> _loadTransportCache(int settlementId, String day, bool favoritesOnly) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_transportCacheKey(settlementId, day, favoritesOnly));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (map['items'] as List<dynamic>?) ?? [];
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getListing(int id) async {
    try {
      return await api.request('/listings/$id', auth: true) as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        throw ApiException('Объявление недоступно или удалено', statusCode: 404);
      }
      rethrow;
    }
  }

  Future<List<dynamic>> loadMyListings() async {
    final data = await api.request('/listings?mine=true&sort=newest&limit=100&offset=0', auth: true);
    if (data is Map) {
      return (data['items'] as List<dynamic>?) ?? [];
    }
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> loadMyListingStats() async {
    return await api.request('/listings/mine/stats', auth: true) as Map<String, dynamic>;
  }

  Future<void> deleteListing(int id) async {
    await api.request('/listings/$id', method: 'DELETE', auth: true);
    await loadListings();
    notifyListeners();
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

  Future<void> reportDirectory(int id, {required String reason, String? note}) async {
    await api.request(
      '/directory/$id/report',
      method: 'POST',
      auth: true,
      body: {'reason': reason, 'note': note},
    );
  }

  Future<void> trackDirectoryView(int id) async {
    try {
      await api.request('/directory/$id/view', method: 'POST');
    } catch (_) {}
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
    bool asDraft = false,
  }) async {
    final payload = {...body, 'as_draft': asDraft};
    var updated = await api.request('/listings/$id', method: 'PATCH', auth: true, body: payload) as Map<String, dynamic>;
    if (imagePaths.isNotEmpty) {
      updated = await api.uploadListingImages(id, imagePaths);
    }
    await loadListings();
    notifyListeners();
    return updated;
  }

  Future<Map<String, dynamic>> createListing(
    Map<String, dynamic> body, {
    List<String> imagePaths = const [],
    bool asDraft = false,
  }) async {
    final payload = {...body, 'as_draft': asDraft};
    final created = await api.request('/listings', method: 'POST', auth: true, body: payload) as Map<String, dynamic>;
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

  Future<List<dynamic>> loadAuthorListings(int authorId) async {
    final data = await api.request(
      '/listings?author_id=$authorId&sort=newest&limit=50&offset=0',
      auth: true,
    );
    if (data is Map) return (data['items'] as List<dynamic>?) ?? [];
    return data as List<dynamic>;
  }

  Future<List<dynamic>> loadNotifications() async {
    return await api.request('/notifications', auth: true) as List<dynamic>;
  }

  Future<void> refreshUnreadNotifications({bool announceLocal = false}) async {
    if (user == null) {
      unreadNotifications = 0;
      notifyListeners();
      return;
    }
    try {
      final before = unreadNotifications;
      final data = await api.request('/notifications/unread-count', auth: true) as Map<String, dynamic>;
      unreadNotifications = (data['count'] as num?)?.toInt() ?? 0;
      notifyListeners();
      if (announceLocal && unreadNotifications > before) {
        await PushService.instance.showLocal(
          title: 'Рядом56',
          body: unreadNotifications == 1
              ? 'Новое уведомление'
              : 'Новые уведомления: $unreadNotifications',
          data: {'type': 'inbox'},
        );
      }
    } catch (_) {}
  }

  Future<void> markNotificationRead(int id) async {
    await api.request('/notifications/$id/read', method: 'POST', auth: true);
    await refreshUnreadNotifications();
  }

  Future<void> markAllNotificationsRead() async {
    await api.request('/notifications/read-all', method: 'POST', auth: true);
    unreadNotifications = 0;
    notifyListeners();
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

  Future<void> uploadAvatar(String filePath) async {
    user = await api.uploadAvatar(filePath);
    notifyListeners();
  }

  Future<void> deleteAvatar() async {
    user = await api.request('/auth/me/avatar', method: 'DELETE', auth: true) as Map<String, dynamic>;
    notifyListeners();
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

  Future<void> _loadViewHistory(SharedPreferences prefs) async {
    final raw = prefs.getString('view_history');
    if (raw == null || raw.isEmpty) {
      viewHistory = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      viewHistory = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      viewHistory = [];
    }
  }

  Future<void> addViewHistory(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id is! int) return;
    viewHistory.removeWhere((e) => e['id'] == id);
    viewHistory.insert(0, {
      'id': id,
      'title': item['title'],
      'category': item['category'],
      'price': item['price'],
      'settlement_name': item['settlement_name'],
      'images': item['images'],
      'author_id': item['author_id'],
      'is_urgent': item['is_urgent'] == true,
      'is_pinned': item['is_pinned'] == true,
    });
    if (viewHistory.length > 30) {
      viewHistory = viewHistory.take(30).toList();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('view_history', jsonEncode(viewHistory));
    notifyListeners();
  }

  Future<void> clearViewHistory() async {
    viewHistory = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('view_history');
    notifyListeners();
  }

  Future<Map<String, dynamic>> toggleDirectoryFavorite(int id, {bool? currentlyFavorited}) async {
    final was = currentlyFavorited ?? directoryFavoriteIds.contains(id);
    final updated = was
        ? await api.request('/directory/$id/favorite', method: 'DELETE', auth: true) as Map<String, dynamic>
        : await api.request('/directory/$id/favorite', method: 'POST', auth: true) as Map<String, dynamic>;
    final favorited = updated['is_favorited'] == true;
    if (favorited) {
      directoryFavoriteIds.add(id);
    } else {
      directoryFavoriteIds.remove(id);
    }
    for (var i = 0; i < directory.length; i++) {
      final item = directory[i];
      if (item is Map && item['id'] == id) {
        directory[i] = {...Map<String, dynamic>.from(item), 'is_favorited': favorited};
      }
    }
    notifyListeners();
    return updated;
  }

  Future<List<dynamic>> loadDirectoryFavorites() async {
    final rows = await api.request('/directory/favorites', auth: true) as List<dynamic>;
    directoryFavoriteIds
      ..clear()
      ..addAll(rows.whereType<Map>().where((e) => e['id'] is int).map((e) => e['id'] as int));
    notifyListeners();
    return rows;
  }

  Future<String> requestPasswordReset(String email) async {
    final data = await api.request('/auth/forgot-password', method: 'POST', body: {
      'email': email,
    });
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return 'Если такой email есть в системе, мы отправили код на почту';
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String password,
  }) async {
    await api.request('/auth/reset-password', method: 'POST', body: {
      'email': email,
      'code': code,
      'password': password,
    });
  }

  Future<String> _ensureDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('ryadom_device_id');
    if (id != null && id.length >= 16) return id;
    final rand = Random.secure();
    id = List.generate(16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString('ryadom_device_id', id);
    return id;
  }

  Future<List<Map<String, dynamic>>> loadDeviceSessions() async {
    final rows = await api.request('/auth/sessions', auth: true) as List<dynamic>;
    return rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> revokeAllSessions() async {
    await api.request('/auth/sessions/revoke-all', method: 'POST', auth: true);
    await logout(keepPinBackup: false);
  }

  Future<void> revokeOtherSessions() async {
    await api.request('/auth/sessions/revoke-others', method: 'POST', auth: true);
  }

  Future<void> revokeSession(int id, {required bool isCurrent}) async {
    await api.request('/auth/sessions/$id', method: 'DELETE', auth: true);
    if (isCurrent) {
      await logout(keepPinBackup: false);
    }
  }

  Future<void> login(String email, String password) async {
    final data = await api.request('/auth/login', method: 'POST', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    final token = data['access_token'] as String;
    await api.setToken(token);
    await PinStorage.saveSessionToken(token);
    _hasPinSession = true;
    user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
    hasPin = await PinStorage.hasPin();
    // Пароль уже введён — сессия разблокирована; если PIN нет, RootGate/экран входа
    // отправят на обязательную настройку.
    pinUnlocked = true;
    await reportDeviceInfo();
    await refreshPublic();
    await refreshUnreadNotifications();
    await refreshUnreadChats();
    notifyListeners();
  }

  Future<void> register(Map<String, dynamic> body) async {
    final data = await api.request('/auth/register', method: 'POST', body: body) as Map<String, dynamic>;
    final token = data['access_token'] as String;
    await api.setToken(token);
    await PinStorage.saveSessionToken(token);
    _hasPinSession = true;
    user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
    hasPin = await PinStorage.hasPin();
    pinUnlocked = true;
    await reportDeviceInfo();
    await refreshPublic();
    await refreshUnreadNotifications();
    await refreshUnreadChats();
    notifyListeners();
  }

  Future<void> logout({bool keepPinBackup = true}) async {
    // Резервный токен оставляем, если PIN есть — можно войти по PIN снова.
    final keepPinSession = keepPinBackup && (hasPin || await PinStorage.hasPin());
    final current = await api.token;
    if (keepPinSession && current != null) {
      await PinStorage.saveSessionToken(current);
      _hasPinSession = true;
    } else {
      await PinStorage.saveSessionToken(null);
      _hasPinSession = false;
    }
    await api.setToken(null);
    user = null;
    pinUnlocked = false;
    favorites = [];
    favoriteIds.clear();
    directoryFavoriteIds.clear();
    transportFavoriteIds.clear();
    unreadNotifications = 0;
    unreadChats = 0;
    await loadListings();
    notifyListeners();
  }
}