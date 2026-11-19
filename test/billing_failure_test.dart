import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/data/purchases_service.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Billing that always fails, like a build without a store key.
class _BrokenBilling implements PurchasesService {
  @override
  Future<void> identify(String userId) async => throw StateError('no store key');
  @override
  Future<bool> isFastTrackActive() async => throw StateError('no store key');
  @override
  Future<String> priceLabel() async => throw StateError('no store key');
  @override
  Future<bool> purchaseFastTrack() async => throw StateError('no store key');
  @override
  Future<bool> restore() async => throw StateError('no store key');
}

void main() {
  test('broken billing never hides the access the server granted (trial or paid)', () async {
    final backend = DemoBackend();
    await backend.verifyOtp(OtpChannel.email, 'asha@example.com', '123456');
    final c = ProviderContainer(
      overrides: [backendProvider.overrideWithValue(backend), purchasesProvider.overrideWithValue(_BrokenBilling())],
    );
    addTearDown(c.dispose);
    c.listen(authUserProvider, (_, _) {});
    c.listen(premiumProvider, (_, _) {});
    await c.read(authUserProvider.future);
    backend.setPremium(true); // the server says: paid plan or active trial
    expect(await c.read(premiumProvider.future), isTrue);
  });

  test('server demo payment unlocks Fast-Track through the backend, not the app', () async {
    final backend = DemoBackend();
    await backend.verifyOtp(OtpChannel.email, 'asha@example.com', '123456');
    expect(await backend.paymentsMode(), 'demo');
    final purchases = ServerDemoPurchases(backend);
    expect(await purchases.isFastTrackActive(), isFalse);
    expect(await purchases.purchaseFastTrack(), isTrue);
    expect(await backend.serverPremium(), isTrue);
  });
}
