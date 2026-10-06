import 'package:flutter_test/flutter_test.dart';

import 'package:attendence/core/device_services.dart';

/// Attendance may not be marked without a location, so every blocked case has
/// to name the thing the employee must change.
void main() {
  group('LocationResult', () {
    test('a block is never usable and always explains itself', () {
      for (final block in [
        LocationBlock.serviceDisabled,
        LocationBlock.permissionDenied,
        LocationBlock.permissionForever,
        LocationBlock.noFix,
      ]) {
        final result = LocationResult.blocked(block);

        expect(result.ok, isFalse, reason: '$block');
        expect(result.location, isNull, reason: '$block');
        expect(result.message, isNotEmpty, reason: '$block');
      }
    });

    test('only the cases a settings screen can fix offer a button', () {
      expect(
        const LocationResult.blocked(LocationBlock.serviceDisabled).actionLabel,
        'Turn on GPS',
      );
      expect(
        const LocationResult.blocked(LocationBlock.permissionForever)
            .actionLabel,
        'Open settings',
      );

      // A timed-out fix is not a setting — retrying is the only cure.
      expect(
        const LocationResult.blocked(LocationBlock.noFix).actionLabel,
        isNull,
      );
      expect(
        const LocationResult.blocked(LocationBlock.permissionDenied)
            .actionLabel,
        isNull,
      );
    });

    test('an unblocked result carries no message', () {
      const result = LocationResult.blocked(LocationBlock.none);
      expect(result.message, isEmpty);
      expect(result.actionLabel, isNull);
    });
  });
}
