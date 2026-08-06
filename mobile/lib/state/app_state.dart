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
  List<dynamic> directory = [];
  String? error;

  String? filterCategory;
  int? filterSettlementId;
  String filterQuery = '';
  String sort = 'newest';
  bool listingsLoading = false;

  String? directoryCategory;
  int? directorySettlementId;
  String directoryQuery = '';
  bool directoryLoading = false;

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
    } catch (e) {
      error = e.toString();
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

  Future<void> loadListings() async {
    listingsLoading = true;
    notifyListeners();
    try {
      final params = <String, String>{'sort': sort};
      if (filterCategory != null) params['category'] = filterCategory!;
      if (filterSettlementId != null) params['settlement_id'] = '$filterSettlementId';
      if (filterQuery.trim().isNotEmpty) params['q'] = filterQuery.trim();
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      listings = await api.request('/listings?$qs') as List<dynamic>;
    } finally {
      listingsLoading = false;
      notifyListeners();
    }
  }

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
    notifyListeners();
  }

  Future<void> createListing(Map<String, dynamic> body) async {
    await api.request('/listings', method: 'POST', auth: true, body: body);
    await loadListings();
  }
}
