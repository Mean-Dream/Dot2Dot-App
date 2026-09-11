import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'home_page.dart';
import 'services/analytics_service.dart';
import 'services/consent_service.dart';

class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _analytics = false;
  bool _crash = false;
  bool _saving = false;

  Future<void> _save({bool acceptAll = false}) async {
    if (_saving) return;
    setState(() => _saving = true);

    final analytics = acceptAll ? true : _analytics;
    final crash = acceptAll ? true : _crash;

    await ConsentService.save(analytics: analytics, crash: crash);

    if (analytics && !AnalyticsService.isReady) {
      try {
        await AnalyticsService.initialize();
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // Header
              Icon(Icons.lock_outline_rounded, size: 48, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                'Your privacy matters',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'WonderDot uses a small number of third-party services to '
                'improve your experience. You choose what we collect.',
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.65),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              // Analytics toggle
              _ConsentToggle(
                icon: Icons.bar_chart_rounded,
                title: 'Analytics',
                description:
                    'Helps us understand which features are used so we can '
                    'make WonderDot better. No personal data is shared.',
                value: _analytics,
                onChanged: (v) => setState(() => _analytics = v),
              ),

              const Divider(height: 32),

              // Crash reporting toggle
              _ConsentToggle(
                icon: Icons.bug_report_outlined,
                title: 'Crash reports',
                description:
                    'Automatically sends anonymous crash logs so we can fix '
                    'bugs faster. No puzzle content or account data is included.',
                value: _crash,
                onChanged: (v) => setState(() => _crash = v),
              ),

              const Spacer(),

              // Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : () => _save(acceptAll: true),
                  child: _saving
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : const Text(
                          'Accept all',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: cs.outline.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  onPressed: _saving ? null : () => _save(),
                  child: Text(
                    'Save my preferences',
                    style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Privacy policy link
              Center(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                    children: [
                      const TextSpan(text: 'Read our '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(
                          color: cs.primary,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => launchUrl(
                                Uri.parse(AppConfig.privacyPolicyUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentToggle extends StatelessWidget {
  const _ConsentToggle({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 22, color: cs.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: cs.primary,
        ),
      ],
    );
  }
}
