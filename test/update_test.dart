import 'package:flutter_test/flutter_test.dart';
import 'package:tv_channels/update.dart';

const dl = 'https://github.com/Ken-n7/reLiveTV/releases/download/v1.2.0';

void main() {
  test('version comparison', () {
    expect(compareVersions('1.2.10', '1.2.9')! > 0, isTrue);
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0')! < 0, isTrue);
    expect(compareVersions('1.0', '1.0.0'), isNull);
    expect(compareVersions('1.0.0-dev', '1.0.0'), isNull);
  });

  test('latest release comes from its SHA256SUMS; links are always this repo\'s', () {
    final a = 'a' * 64, b = 'b' * 64, c = 'c' * 64;
    final r = releaseFromSums('$a  relivetv-1.2.0-android-arm64-v8a.apk\n$b  relivetv-1.2.0-linux-x64.tar.gz\n$c  ../evil.apk\n')!;
    expect(r.version, '1.2.0');
    expect(r.pageUrl, 'https://github.com/Ken-n7/reLiveTV/releases/tag/v1.2.0');
    expect(r.assets, {
      'relivetv-1.2.0-android-arm64-v8a.apk': '$dl/relivetv-1.2.0-android-arm64-v8a.apk',
      'relivetv-1.2.0-linux-x64.tar.gz': '$dl/relivetv-1.2.0-linux-x64.tar.gz',
    });
    expect(r.sums['relivetv-1.2.0-android-arm64-v8a.apk'], a);
    expect(r.sums.containsKey('../evil.apk'), isFalse);
    expect(releaseFromSums('<html>not found</html>'), isNull);
  });

  test('APK for this device CPU', () {
    final r = Release('1.2.0', '', {'relivetv-1.2.0-android-armeabi-v7a.apk': 'u', 'relivetv-1.2.0-android-arm64-v8a.apk': 'u'});
    expect(apkFor(r, ['arm64-v8a', 'armeabi-v7a']), 'relivetv-1.2.0-android-arm64-v8a.apk');
    expect(apkFor(r, ['x86']), isNull);
  });

  test('checksum file parsing', () {
    final a = 'a' * 64, b = 'b' * 64;
    expect(parseSums('$a  relivetv.apk\n$b *SHA256SUMS\nnot a line\n'), {'relivetv.apk': a, 'SHA256SUMS': b});
  });
}
