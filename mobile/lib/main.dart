import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'push_service.dart';
import 'screens/home_shell.dart';
import 'screens/listing_chat_screen.dart';
import 'screens/listing_detail_screen.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.instance.init();
  final prefs = await SharedPreferences.getInstance();
  const fromBuild = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://155.212.174.201:8080/api',
  );
  var apiBase = prefs.getString('api_base') ?? fromBuild;
  // Сбрасываем старые локальные адреса (LAN / localhost)
  if (apiBase.contains('192.168.') ||
      apiBase.contains('127.0.0.1') ||
      apiBase.contains('localhost') ||
      apiBase.contains('10.0.')) {
    apiBase = fromBuild;
  }
  await prefs.setString('api_base', apiBase);
  runApp(RyadomApp(apiBase: apiBase));
}

class RyadomApp extends StatefulWidget {
  const RyadomApp({super.key, required this.apiBase});

  final String apiBase;

  @override
  State<RyadomApp> createState() => _RyadomAppState();
}

class _RyadomAppState extends State<RyadomApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState(ApiClient(baseUrl: widget.apiBase))..bootstrap();
    PushService.instance.onTap = _handlePushTap;
  }

  Future<void> _handlePushTap(Map<String, dynamic> data) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final type = data['type']?.toString();
    final listingId = int.tryParse('${data['listing_id'] ?? ''}');
    final buyerId = int.tryParse('${data['buyer_id'] ?? ''}');

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
    if ((type == 'listing_approved' || type == 'listing_rejected') && listingId != null) {
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
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child ?? const SizedBox.shrink(),
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
    if (state.needsPinSetup) return const PinSetupScreen(allowSkip: false);
    if (state.needsPinUnlock) return const PinUnlockScreen();
    return const HomeShell();
  }
}
