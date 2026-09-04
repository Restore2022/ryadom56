import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'call_screens.dart';
import 'call_service.dart';
import 'api.dart';
import 'error_reporter.dart';
import 'push_service.dart';
import 'screens/home_shell.dart';
import 'screens/listing_chat_screen.dart';
import 'screens/listing_detail_screen.dart';
import 'screens/ride_chat_screen.dart';
import 'screens/ride_detail_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/pin_unlock_screen.dart';
import 'screens/register_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

bool _isStaleApiBase(String apiBase) {
  final u = apiBase.toLowerCase();
  return u.contains('192.168.') ||
      u.contains('127.0.0.1') ||
      u.contains('localhost') ||
      u.contains('10.0.2.2') ||
      u.contains('10.0.3.2') ||
      u.contains('155.212.174.201') ||
      u.startsWith('http://legac.ru') ||
      u.contains('www.legac.ru');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await PushService.instance.init();
  final prefs = await SharedPreferences.getInstance();
  const fromBuild = String.fromEnvironment(
    'API_BASE',
    defaultValue: kProductionApiBase,
  );
  var apiBase = prefs.getString('api_base') ?? fromBuild;
  // LAN / старый IP:8080 / http без TLS — на прод-домен
  if (_isStaleApiBase(apiBase)) {
    apiBase = fromBuild;
  }
  await prefs.setString('api_base', apiBase);
  final api = ApiClient(baseUrl: apiBase);
  ErrorReporter.attach(api);
  runApp(RyadomApp(apiBase: apiBase, api: api));
}

class RyadomApp extends StatefulWidget {
  const RyadomApp({super.key, required this.apiBase, required this.api});

  final String apiBase;
  final ApiClient api;

  @override
  State<RyadomApp> createState() => _RyadomAppState();
}

class _RyadomAppState extends State<RyadomApp> {
  late final AppState _state;
  bool _callsOn = false;

  @override
  void initState() {
    super.initState();
    _state = AppState(widget.api)..bootstrap();
    _state.addListener(_syncCalls);
    PushService.instance.onTap = _handlePushTap;
    PushService.instance.onForegroundData = (data) {
      final type = data['type']?.toString();
      if (type == 'incoming_call') {
        CallService.instance.handlePush(data);
      } else if (type == 'listing_message' || type == 'ride_message') {
        _state.refreshUnreadChats();
      }
    };
    CallService.instance.attach(widget.api);
  }

  @override
  void dispose() {
    _state.removeListener(_syncCalls);
    super.dispose();
  }

  void _syncCalls() {
    final on = _state.user != null && _state.pinUnlocked;
    final uid = _state.user?['id'] as int?;
    if (uid != null) CallService.instance.myUserId = uid;
    if (on && !_callsOn) {
      _callsOn = true;
      CallService.instance.attach(widget.api);
      CallService.instance.connect();
    } else if (!on && _callsOn) {
      _callsOn = false;
      CallService.instance.disconnect();
    }
  }

  Future<void> _handlePushTap(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    if (type == 'incoming_call' || type == 'missed_call') {
      await CallService.instance.handlePush(data);
      if (type == 'incoming_call') return;
    }
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final listingId = int.tryParse('${data['listing_id'] ?? ''}');
    final buyerId = int.tryParse('${data['buyer_id'] ?? ''}');
    final rideId = int.tryParse('${data['ride_id'] ?? ''}');
    final passengerId = int.tryParse('${data['passenger_id'] ?? ''}');

    if (type == 'ride_message' && rideId != null) {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => RideChatScreen(
            rideId: rideId,
            title: 'Чат по попутке',
            peerId: passengerId,
          ),
        ),
      );
      return;
    }
    if (type == 'ride_new' && rideId != null) {
      await nav.push(
        MaterialPageRoute(builder: (_) => RideDetailScreen(rideId: rideId)),
      );
      return;
    }

    if (type == 'listing_message' && listingId != null) {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => ListingChatScreen(
            listingId: listingId,
            listingTitle: 'Чат по объявлению',
            peerId: buyerId,
          ),
        ),
      );
      return;
    }
    if ((type == 'listing_approved' || type == 'listing_rejected' || type == 'listing_relevance') && listingId != null) {
      await nav.push(
        MaterialPageRoute(builder: (_) => ListingDetailScreen(listingId: listingId)),
      );
      return;
    }
    if (type == 'district_alert') {
      await nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      return;
    }
    await nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _state,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Рядом56',
            debugShowCheckedModeBanner: false,
            theme: buildRyadomTheme(Brightness.light),
            darkTheme: buildRyadomTheme(Brightness.dark),
            themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final scale = mq.textScaler.scale(1).clamp(0.9, 1.25);
              var padding = mq.padding;
              if (mq.viewInsets.bottom < 40) {
                padding = padding.copyWith(
                  left: math.max(padding.left, mq.viewPadding.left),
                  right: math.max(padding.right, mq.viewPadding.right),
                  bottom: math.max(padding.bottom, mq.viewPadding.bottom),
                );
              }
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: padding,
                ),
                child: CallOverlayHost(child: child ?? const SizedBox.shrink()),
              );
            },
            routes: {
              '/': (_) => const RootGate(),
              '/login': (_) => const LoginScreen(),
              '/forgot-password': (_) => const ForgotPasswordScreen(),
              '/register': (_) => const RegisterScreen(),
              '/home': (_) => const HomeShell(),
            },
          );
        },
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.booting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Рядом56', style: GoogleFonts.unbounded(fontSize: 28, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    if (!state.onboardingDone) return const OnboardingScreen();
    if (state.needsPinSetup) return const PinSetupScreen(allowSkip: true);
    if (state.needsPinUnlock) return const PinUnlockScreen();
    return const HomeShell();
  }
}
