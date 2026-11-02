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

  test('release parsing keeps only this repo\'s download links', () {
    final r = parseRelease({
      'tag_name': 'v1.2.0',
      'html_url': 'https://github.com/Ken-n7/reLiveTV/releases/tag/v1.2.0',
      'assets': [
        {'name': 'relivetv-1.2.0-android-arm64-v8a.apk', 'browser_download_url': '$dl/relivetv-1.2.0-android-arm64-v8a.apk'},
        {'name': 'SHA256SUMS', 'browser_download_url': '$dl/SHA256SUMS'},
        {'name': 'evil.apk', 'browser_download_url': 'https://evil.example/evil.apk'},
        {'name': '../x.apk', 'browser_download_url': '$dl/x.apk'},
      ],
    })!;
    expect(r.version, '1.2.0');
    expect(r.assets.keys, ['relivetv-1.2.0-android-arm64-v8a.apk', 'SHA256SUMS']);
    expect(parseRelease({'tag_name': 'nightly'}), isNull);
    expect(parseRelease('garbage'), isNull);
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
