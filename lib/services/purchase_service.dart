import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config.dart';

class PurchaseService {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    final config = PurchasesConfiguration(AppConfig.revenueCatAndroidKey);
    await Purchases.configure(config);
  }

  static Future<bool> isPremium() async {
    if (kIsWeb) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey('premium');
    } catch (_) {
      return false;
    }
  }

  static Future<Offerings?> getOfferings() async {
    if (kIsWeb) return null;
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> purchase(Package package) async {
    try {
      final info = await Purchases.purchasePackage(package);
      return info.entitlements.active.containsKey('premium');
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  static Future<bool> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey('premium');
    } catch (_) {
      return false;
    }
  }
}
