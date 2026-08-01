import 'package:codexcli_remote/data/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy certificate fields are ignored when loading a profile', () {
    final profile = ServerProfile.fromJson({
      'id': 'server-1',
      'name': 'WSL',
      'url': 'ws://100.64.0.10:9999',
      'allowBadCertificate': true,
      'pinnedCertSha256': 'legacy-fingerprint',
    }, token: 'secret');

    expect(profile.id, 'server-1');
    expect(profile.url, 'ws://100.64.0.10:9999');
    expect(profile.bearerToken, 'secret');
    expect(profile.toJson(), {
      'id': 'server-1',
      'name': 'WSL',
      'url': 'ws://100.64.0.10:9999',
    });
  });
}
