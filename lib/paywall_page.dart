import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'services/purchase_service.dart';

class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  Offerings? _offerings;
  bool _loading = true;
  bool _purchasing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offerings = await PurchaseService.getOfferings();
    if (mounted) {
      setState(() {
        _offerings = offerings;
        _loading = false;
      });
    }
  }

  Future<void> _purchase(Package package) async {
    setState(() => _purchasing = true);
    try {
      final success = await PurchaseService.purchase(package);
      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _purchasing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _error = 'Purchase failed. Please try again.';
        });
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    final success = await PurchaseService.restore();
    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _purchasing = false;
          _error = 'No active subscription found.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111E18),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _purchasing
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.star_rounded, size: 56, color: Color(0xFF4EFE98)),
                        const SizedBox(height: 16),
                        const Text(
                          'WonderDot Premium',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Unlock the full experience',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 15),
                        ),
                        const SizedBox(height: 32),
                        _buildBenefit(Icons.all_inclusive, 'Unlimited puzzles'),
                        _buildBenefit(Icons.picture_as_pdf_outlined, 'Export puzzles as PDF'),
                        _buildBenefit(Icons.devices, 'Works on all your devices'),
                        const SizedBox(height: 36),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                        ],
                        ..._buildPackageButtons(),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _restore,
                          child: const Text(
                            'Restore purchases',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4EFE98), size: 22),
          const SizedBox(width: 14),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  List<Widget> _buildPackageButtons() {
    final packages = _offerings?.current?.availablePackages ?? [];
    if (packages.isEmpty) {
      return [
        const Text(
          'No plans available. Please try again later.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      ];
    }

    // Sort: annual first, then monthly
    packages.sort((a, b) {
      const order = {PackageType.annual: 0, PackageType.monthly: 1};
      return (order[a.packageType] ?? 9).compareTo(order[b.packageType] ?? 9);
    });

    return packages.map((pkg) {
      final isAnnual = pkg.packageType == PackageType.annual;
      final priceStr = pkg.storeProduct.priceString;
      final label = isAnnual ? 'Annual' : 'Monthly';
      final sublabel = isAnnual ? 'Best value' : null;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isAnnual
                ? const Color(0xFF4EFE98)
                : const Color(0xFF253B30),
            foregroundColor: isAnnual ? const Color(0xFF111E18) : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _purchase(pkg),
          child: Column(
            children: [
              Text(
                '$label — $priceStr',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              if (sublabel != null)
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: isAnnual
                        ? const Color(0xFF111E18).withValues(alpha: 0.7)
                        : Colors.white54,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

/// Push the paywall and return true if the user subscribed.
Future<bool> showPaywall(BuildContext context) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const PaywallPage()),
  );
  return result == true;
}
