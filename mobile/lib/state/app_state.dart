import 'package:flutter/foundation.dart';

import '../api.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  bool booting = true;
  Map<String, dynamic>? user;
  List<dynamic> settlements = [];
  List<dynamic> listings = [];
  List<dynamic> directory = [];
  String? error;

  Future<void> bootstrap() async {
    try {
      settlements = await api.request('/settlements') as List<dynamic>;
      final token = await api.token;
      if (token != null) {
        user = await api.request('/auth/me', auth: true) as Map<String, dynamic>;
      }
      await refreshPublic();
    } catch (e) {
      error = e.toString();
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> refreshPublic() async {
    listings = await api.request('/listings') as List<dynamic>;
    directory = await api.request('/directory') as List<dynamic>;
    notifyListeners();
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
    await refreshPublic();
  }
}
