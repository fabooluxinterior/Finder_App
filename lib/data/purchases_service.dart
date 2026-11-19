import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/config.dart';
import 'backend.dart';
import 'demo_backend.dart';

abstract class PurchasesService {
  Future<void> identify(String userId);
  Future<bool> isFastTrackActive();

  /// Localised store price, e.g. "₹79.00".
  Future<String> priceLabel();

  /// Returns true when the Fast-Track entitlement is active afterwards.
  /// Returns false if the user cancelled.
  Future<bool> purchaseFastTrack();
  Future<bool> restore();
}

/// RevenueCat + Google Play Billing. Google Play's sheet offers UPI / Google Pay
/// natively for INR, so no separate payment integration is needed.
class RevenueCatPurchases implements PurchasesService {
  bool _configured = false;

  @override
  Future<void> identify(String userId) async {
    if (!_configured) {
      await Purchases.configure(PurchasesConfiguration(AppConfig.revenueCatAndroidKey)..appUserID = userId);
      _configured = true;
    } else {
      await Purchases.logIn(userId);
    }
  }

  bool _active(CustomerInfo info) => info.entitlements.active.containsKey(AppConfig.entitlementId);

  @override
  Future<bool> isFastTrackActive() async => _active(await Purchases.getCustomerInfo());

  Future<Package?> _package() async {
    final offerings = await Purchases.getOfferings();
    final packages = [...?offerings.current?.availablePackages, for (final o in offerings.all.values) ...o.availablePackages];
    for (final p in packages) {
      // Play subscription ids surface as "<productId>:<basePlanId>".
      if (p.storeProduct.identifier.split(':').first == AppConfig.productId) return p;
    }
    return null;
  }

  @override
  Future<String> priceLabel() async => (await _package())?.storeProduct.priceString ?? '₹79';

  @override
  Future<bool> purchaseFastTrack() async {
    final pkg = await _package();
    if (pkg == null) throw StateError('Fast-Track pass is not available right now.');
    // No free trial: always buy the plain base plan, never an offer phase
    // (RevenueCat's default option would pick the longest free trial).
    final basePlan = pkg.storeProduct.subscriptionOptions?.where((o) => o.isBasePlan).firstOrNull;
    try {
      final result = await Purchases.purchase(
        basePlan != null ? PurchaseParams.subscriptionOption(basePlan) : PurchaseParams.package(pkg),
      );
      return _active(result.customerInfo);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  @override
  Future<bool> restore() async => _active(await Purchases.restorePurchases());
}

class DemoPurchases implements PurchasesService {
  DemoPurchases(this._backend);
  final DemoBackend _backend;

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<bool> isFastTrackActive() async => _backend.premium;

  @override
  Future<String> priceLabel() async => '₹79';

  @override
  Future<bool> purchaseFastTrack() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    _backend.setPremium(true);
    return true;
  }

  @override
  Future<bool> restore() async => _backend.premium;
}

/// Used while Google Play billing isn't set up (no RevenueCat key in the build):
/// a "purchase" asks the server for a demo plan, which only works while the
/// server's demo-payment window is open. Nothing is charged, and the app can't
/// grant itself access: the server decides.
class ServerDemoPurchases implements PurchasesService {
  ServerDemoPurchases(this._backend);
  final FinderBackend _backend;

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<bool> isFastTrackActive() async => false; // the server's access status is the source of truth

  @override
  Future<String> priceLabel() async => '₹79';

  @override
  Future<bool> purchaseFastTrack() async {
    await _backend.demoActivateFastTrack();
    return _backend.serverPremium();
  }

  @override
  Future<bool> restore() async => _backend.serverPremium();
}
