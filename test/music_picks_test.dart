import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pick favorites without Spotify login: search, save, shown on the profile', () async {
    final b = DemoBackend();
    await b.verifyOtp(OtpChannel.email, 'asha@example.com', '123456');
    final r = await b.searchMusic('shreya');
    expect(r.artists.map((a) => a.name), ['Shreya Ghoshal']);
    expect((await b.searchMusic('s')).artists, isEmpty);

    await b.saveMusicPicks(artists: r.artists, tracks: (await b.searchMusic('evening')).tracks);
    final m = await b.musicState();
    expect(m.connected, isTrue);
    expect(m.artists.single.name, 'Shreya Ghoshal');
    expect(m.topTracks.single.rank, 1);

    await b.disconnectMusic();
    expect((await b.musicState()).connected, isFalse);
  });
}
