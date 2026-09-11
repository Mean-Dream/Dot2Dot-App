import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  void _showError(String msg) {
    if (mounted) setState(() => _errorMessage = msg);
  }

  Future<void> _handleAuth(bool isSignUp) async {
    _clearError();
    setState(() => _isLoading = true);
    try {
      if (isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check your email to confirm your account, then sign in.')),
          );
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('email not confirmed')) {
        _showError('Email not confirmed — check your inbox for a confirmation link, or use "Forgot your password?" to set one.');
      } else if (msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials') ||
          msg.contains('email not found') ||
          msg.contains('wrong password')) {
        _showError('Wrong email or password. If you signed up with Google, use "Continue with Google" instead.');
      } else if (msg.contains('too many requests') || msg.contains('rate limit')) {
        _showError('Too many attempts — please wait a moment and try again.');
      } else {
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleMagicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email above first.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: AppConfig.webAppUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Magic link sent — check your inbox and click the link to sign in.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 10),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final String redirectTo = kIsWeb
          ? AppConfig.webAppUrl
          : 'wonderdot://auth-callback';

      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    // Use the email already typed in the main field — no dialog needed.
    // Opening a dialog pushes a new Navigator route; when that route is
    // popped, Supabase may fire a passwordRecovery auth event that causes
    // main.dart's StreamBuilder to switch pages mid-teardown, triggering
    // the _dependents.isEmpty framework assertion.
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email address above, then tap "Forgot your password?".'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final String redirectTo = kIsWeb
          ? AppConfig.webAppUrl
          : 'wonderdot://reset-callback';

      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
      );

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Reset link sent — check your inbox.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 6),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not send reset link — please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen radial gradient matching icon background ─────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [
                    Color(0xFF111B56), // warmer navy at centre
                    Color(0xFF060A20), // very dark at edges
                  ],
                ),
              ),
            ),
          ),

          // ── Decorative constellation dots (mirrors the icon's colour palette) ─
          Positioned.fill(
            child: CustomPaint(painter: _CosmicBackgroundPainter(cs.primary)),
          ),

          // ── Content ────────────────────────────────────────────────────────────
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon — ClipRRect removes the white corners from the PNG
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 96,
                        height: 96,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'WonderDot',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Connect the dots. Reveal the picture.',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.45),
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Glassmorphic form card ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1544).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.18),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.07),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Google
                          SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _signInWithGoogle,
                              icon: _GoogleLogoIcon(),
                              label: const Text(
                                'Continue with Google',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.onSurface,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.05),
                                side: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.35),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: cs.outline.withValues(alpha: 0.2),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'or',
                                  style: TextStyle(
                                    color: cs.onSurface.withValues(alpha: 0.35),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: cs.outline.withValues(alpha: 0.2),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 22),

                          // Email
                          TextField(
                            controller: _emailController,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: cs.onSurface),
                            onChanged: (_) => _clearError(),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(
                                Icons.mail_outline_rounded,
                                color: cs.primary.withValues(alpha: 0.6),
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.25),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.primary.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.go,
                            style: TextStyle(color: cs.onSurface),
                            onChanged: (_) => _clearError(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                color: cs.primary.withValues(alpha: 0.6),
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.4),
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.25),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.primary.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _handleAuth(false),
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: _handleMagicLink,
                                child: Text(
                                  'Email me a link',
                                  style: TextStyle(
                                    color: cs.onSurface.withValues(alpha: 0.45),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _handleForgotPassword,
                                child: Text(
                                  'Forgot your password?',
                                  style: TextStyle(
                                    color: cs.primary.withValues(alpha: 0.75),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Inline error — visible immediately, clears on edit
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.redAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 4),

                          if (_isLoading)
                            const Center(child: CircularProgressIndicator())
                          else ...[
                            // Sign In — glowing primary button
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: FilledButton(
                                onPressed: () => _handleAuth(false),
                                style: FilledButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Sign Up
                            OutlinedButton(
                              onPressed: () => _handleAuth(true),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    cs.onSurface.withValues(alpha: 0.75),
                                side: BorderSide(
                                  color: cs.outline.withValues(alpha: 0.3),
                                ),
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Don't have an account? Sign Up",
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Legal
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.35),
                        ),
                        children: [
                          const TextSpan(text: 'By signing up you agree to our '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: TextStyle(
                              color: cs.primary.withValues(alpha: 0.65),
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(
                                    Uri.parse(AppConfig.termsUrl),
                                    mode: LaunchMode.externalApplication,
                                  ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              color: cs.primary.withValues(alpha: 0.65),
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(
                                    Uri.parse(AppConfig.privacyPolicyUrl),
                                    mode: LaunchMode.externalApplication,
                                  ),
                          ),
                          const TextSpan(text: '. You confirm you are 13 or older.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the icon's colour palette as soft glowing dots scattered across
/// the background, plus a subtle dot grid.
class _CosmicBackgroundPainter extends CustomPainter {
  const _CosmicBackgroundPainter(this.primary);
  final Color primary;

  // Each entry: (x-fraction, y-fraction, colour, glow-radius)
  static const _accents = [
    (0.10, 0.12, Color(0xFF00E5E5), 36.0), // teal — top left
    (0.08, 0.48, Color(0xFF9B59F5), 28.0), // purple — left
    (0.88, 0.10, Color(0xFFFF4DAD), 30.0), // pink — top right
    (0.50, 0.38, Color(0xFFFFD060), 22.0), // gold — centre
    (0.28, 0.72, Color(0xFF4285F4), 26.0), // blue — lower left
    (0.74, 0.68, Color(0xFFFF6B35), 22.0), // orange — lower right
    (0.82, 0.42, Color(0xFF4FC3F7), 20.0), // sky blue — right
    (0.38, 0.22, Color(0xFFCC4EFF), 18.0), // violet — upper mid
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Tiny dot grid
    final gridPaint = Paint()
      ..color = primary.withValues(alpha: 0.045);
    const gap = 48.0;
    for (double x = gap; x < size.width; x += gap) {
      for (double y = gap; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.5, gridPaint);
      }
    }

    // Accent glow dots
    for (final (xf, yf, color, r) in _accents) {
      final c = Offset(xf * size.width, yf * size.height);

      // Outer glow
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
      // Bright core
      canvas.drawCircle(c, r * 0.35, Paint()..color = color.withValues(alpha: 0.6));
    }
  }

  @override
  bool shouldRepaint(_CosmicBackgroundPainter old) => old.primary != primary;
}

/// Google "G" logo drawn with pure Flutter canvas — no asset needed.
class _GoogleLogoIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width / 2;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.57, 1.57, false,
      Paint()
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.22,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -3.14, 1.22, false,
      Paint()
        ..color = const Color(0xFFEA4335)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.22,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.09, 0.7, false,
      Paint()
        ..color = const Color(0xFFFBBC05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.22,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.79, 0.63, false,
      Paint()
        ..color = const Color(0xFF34A853)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.22,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.11, r * 0.95, size.height * 0.22),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
