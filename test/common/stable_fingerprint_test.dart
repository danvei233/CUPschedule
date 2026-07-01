import 'package:blackbook/src/common/stable_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable JSON fingerprint ignores map key order', () {
    final first = stableJsonFingerprint({
      'semester': {'id': 191, 'name': '2025-2026-2'},
      'courses': [
        {'name': 'A', 'weekday': 1},
      ],
    });
    final second = stableJsonFingerprint({
      'courses': [
        {'weekday': 1, 'name': 'A'},
      ],
      'semester': {'name': '2025-2026-2', 'id': 191},
    });

    expect(first, second);
  });
}
