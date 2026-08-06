import 'package:flutter/foundation.dart';
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

  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      darkMode = prefs.getBool('dark_mode') ?? false;
      settlements = await api.request('/settlements') as List<dynamic>;
      final token = await api.token;
      if (token != null) {
        user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
      }
      await Future.wait([loadListings(), loadDirectory()]);
    } catch (e) {
      error = e.toString();
    } finally {
      booting = false;
      notifyListeners();
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
    directory = await api.request('/directory') as List<dynamic>;
    notifyListeners();
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
    await refreshPublic();
    notifyListeners();
  }

  Future<void> register(Map<String, dynamic> body) async {
    final data = await api.request('/auth/register', method: 'POST', body: body) as Map<String, dynamic>;
    await api.setToken(data['access_token'] as String);
    user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
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
