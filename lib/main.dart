import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'config.dart';
import 'home_page.dart';
import 'password_update_page.dart';
import 'services/analytics_service.dart';
import 'services/purchase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  try {
    await PurchaseService.initialize();
  } catch (e) {
    debugPrint('RevenueCat init failed: $e');
  }
  try {
    await AnalyticsService.initialize();
  } catch (e) {
    debugPrint('Amplitude init failed: $e');
  }
  _initDeepLinks();
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn;
      options.tracesSampleRate = 0.2;
    },
    appRunner: () => runApp(const MyApp()),
  );
}

void _initDeepLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    Supabase.instance.client.auth.getSessionFromUrl(uri);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      /// 🦖 THE JURASSIC MUSEUM THEME OVERHAUL
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(
          0xFF111E18,
        ), // Deep Jungle Background!
        // 🧠 FIXED: Changed CardTheme to CardThemeData
        cardTheme: const CardThemeData(
          color: Color(0xFF253B30), // Moss Green Panels
          elevation: 4,
        ),

        // Customizing App Bar designs globally
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF253B30), // Moss Green App Bars
          foregroundColor: Color(0xFFF1F7F4), // Warm Ivory text/icons
          elevation: 0,
        ),
      ),
      // The StreamBuilder listens for Auth changes (Login/Logout)
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // User arrived via the password-reset email link — show the
          // "set new password" screen before entering the app.
          if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
            return const PasswordUpdatePage();
          }
          if (snapshot.data?.session != null) {
            final uid = snapshot.data!.session!.user.id;
            AnalyticsService.identify(uid);
            return const HomePage();
          }
          return const AuthPage();
        },
      ),
    );
  }
}
