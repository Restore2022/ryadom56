import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Фоновый обработчик FCM (должен быть top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

typedef PushTapHandler = void Function(Map<String, dynamic> data);

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  bool firebaseReady = false;
  bool localReady = false;
  String? token;
  PushTapHandler? onTap;
  PushTapHandler? onForegroundData;
  int _localId = 1000;

  static const _channelId = 'ryadom56_alerts';
  static const _channelName = 'Рядом56';
  static const _channelDesc = 'Сообщения, объявления и срочные оповещения';
  static const _callChannelId = 'ryadom56_calls';
  static const _callChannelName = 'Звонки Рядом56';

  Future<void> init() async {
    await _initLocal();
    await _initFirebase();
  }

  Future<void> _initLocal() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const init = InitializationSettings(android: android, iOS: ios);
    await _local.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        final raw = resp.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          onTap?.call(data);
        } catch (_) {}
      },
    );
    if (Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _callChannelId,
          _callChannelName,
          description: 'Входящие звонки в приложении',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
    }
    localReady = true;
  }

  Future<void> _initFirebase() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen((msg) {
        final data = Map<String, dynamic>.from(msg.data);
        final type = data['type']?.toString();
        if (type == 'incoming_call') {
          onForegroundData?.call(data);
          return;
        }
        if (type == 'listing_message' || type == 'ride_message') {
          onForegroundData?.call(data);
          return;
        }
        final n = msg.notification;
        final title = n?.title ?? msg.data['title']?.toString() ?? 'Рядом56';
        final body = n?.body ?? msg.data['body']?.toString() ?? '';
        showLocal(title: title, body: body, data: data);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        onTap?.call(Map<String, dynamic>.from(msg.data));
      });

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        // отложим до установки onTap из UI
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          onTap?.call(Map<String, dynamic>.from(initial.data));
        });
      }

      token = await messaging.getToken();
      messaging.onTokenRefresh.listen((t) => token = t);
      firebaseReady = true;
    } catch (e) {
      debugPrint('PushService: Firebase unavailable ($e). Local notifications still work.');
      firebaseReady = false;
    }
  }

  Future<String?> ensureToken() async {
    if (!firebaseReady) return token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {}
    return token;
  }

  Future<void> showLocal({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!localReady) return;
    _localId += 1;
    await _local.show(
      _localId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: data == null ? null : jsonEncode(data),
    );
  }
}
