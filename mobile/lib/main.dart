import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const fromBuild = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://192.168.0.110:8000/api',
  );
  final apiBase = prefs.getString('api_base') ?? fromBuild;
  runApp(RyadomApp(apiBase: apiBase));
}

class RyadomApp extends StatelessWidget {
  const RyadomApp({super.key, required this.apiBase});

  final String apiBase;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(ApiClient(baseUrl: apiBase))..bootstrap(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Рядом56',
            debugShowCheckedModeBanner: false,
            theme: buildRyadomTheme(Brightness.light),
            darkTheme: buildRyadomTheme(Brightness.dark),
            themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
            routes: {
              '/': (_) => const RootGate(),
              '/login': (_) => const LoginScreen(),
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
    return const HomeShell();
  }
}
