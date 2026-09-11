import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'config.dart';
import 'consent_page.dart';
import 'home_page.dart';
import 'onboarding_page.dart';
import 'password_update_page.dart';
import 'providers.dart';
import 'services/analytics_service.dart';
import 'services/consent_service.dart';
import 'services/purchase_service.dart';
import 'theme/app_theme.dart';

void main() async {
  // Sentry must be the outermost wrapper so its zone captures all Flutter errors.
  // WidgetsFlutterBinding.ensureInitialized() is called inside appRunner so that
  // the binding and runApp are both in Sentry's zone — avoids the zone-mismatch
  // assertion the Flutter framework emits when they are in different zones.
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn;
      options.tracesSampleRate = 0.2;
      // Drop events when the user has not consented to crash reporting.
      options.beforeSend = (event, hint) =>
          ConsentService.crashGranted ? event : null;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Unlock premium for local testing — flip to false before shipping.
      if (kDebugMode) PurchaseService.debugPremiumOverride = true;

      // Load consent flags before initialising any data-collecting services.
      await ConsentService.loadFromPrefs();

      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      try {
        await PurchaseService.initialize();
      } catch (e) {
        debugPrint('RevenueCat init failed: $e');
      }
      if (ConsentService.analyticsGranted) {
        try {
          await AnalyticsService.initialize();
        } catch (e) {
          debugPrint('Amplitude init failed: $e');
        }
      }
      _initDeepLinks();
      // On web, Sentry's FlutterErrorIntegration crashes during error
      // serialization (dart_rti._eval tree-shaking bug in dart2js). Wrap
      // its handler so the crash stays silent and DevTools still shows the
      // original error.
      if (kIsWeb) {
        final sentryOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          FlutterError.dumpErrorToConsole(details);
          try {
            sentryOnError?.call(details);
          } catch (_) {
            // Sentry's web handler crashed — the error is already in DevTools.
          }
        };
      }
      runApp(const ProviderScope(child: MyApp()));
    },
  );
}

void _initDeepLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    // Only call getSessionFromUrl when the URI actually carries an OAuth
    // code or token — avoids AuthException spam on normal page loads.
    final q = uri.queryParameters;
    final f = uri.fragment;
    if (q.containsKey('code') || f.contains('access_token')) {
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    }
  });
}

/// Checks whether the user has seen onboarding and routes accordingly.
class _RootPage extends StatefulWidget {
  const _RootPage();

  @override
  State<_RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<_RootPage> {
  late final Future<(bool, bool)> _initState = _load();

  Future<(bool, bool)> _load() async {
    final p = await SharedPreferences.getInstance();
    return (
      p.getBool('onboarding_complete') ?? false,
      p.getBool('consent_shown') ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, bool)>(
      future: _initState,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: SizedBox.shrink());
        final (onboarded, consented) = snap.data!;
        if (!onboarded) return const OnboardingPage();
        if (!consented) return const ConsentPage();
        return const HomePage();
      },
    );
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  // Latched when Supabase fires passwordRecovery; cleared on userUpdated or
  // signedOut. Without this, a rapid signedIn event (which Supabase emits
  // right after passwordRecovery) would overwrite the route and send the
  // user back to the auth page instead of the password-update screen.
  bool _isRecovery = false;

  @override
  Widget build(BuildContext context) {
    final themeId = ref.watch(themeProvider);
    final themeData = AppTheme.fromId(themeId).themeData;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themeData,
      scrollBehavior: const _NoScrollbarBehavior(),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final event = snapshot.data?.event;

          debugPrint('[Auth] event=$event session=${snapshot.data?.session?.user.email}');

          if (event == AuthChangeEvent.passwordRecovery) {
            _isRecovery = true;
          } else if (event == AuthChangeEvent.userUpdated ||
              event == AuthChangeEvent.signedOut) {
            _isRecovery = false;
          }

          if (_isRecovery) return const PasswordUpdatePage();

          if (snapshot.data?.session != null) {
            final uid = snapshot.data!.session!.user.id;
            AnalyticsService.identify(uid);
            return const _RootPage();
          }
          return const AuthPage();
        },
      ),
    );
  }
}
