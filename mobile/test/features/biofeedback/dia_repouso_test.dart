import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';

void main() {
  test('round-trips through toJson and fromJson', () {
    final original = DiaRepouso(
      data: DateTime.utc(2026, 8, 3),
      mediaFcRepouso: 68.5,
      mediaVfcRepouso: 45.2,
    );

    final roundTripped = DiaRepouso.fromJson(original.toJson());

    expect(roundTripped.data, DateTime.utc(2026, 8, 3));
    expect(roundTripped.mediaFcRepouso, 68.5);
    expect(roundTripped.mediaVfcRepouso, 45.2);
  });
}
