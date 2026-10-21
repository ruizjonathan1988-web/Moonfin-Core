import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/french_box_office.dart';

void main() {
  for (final (name, list) in [
    ('2020s', frenchHits2020s),
    ('2010s', frenchHits2010s),
    ('all time', frenchHitsAllTime),
  ]) {
    test('the $name list names each film once', () {
      expect(list.toSet(), hasLength(list.length));
      expect(list.every((id) => id > 0), isTrue);
    });
  }

  test('the record holders of the decade are in the all-time list', () {
    expect(frenchHitsAllTime, contains(frenchHits2010s.first));
    expect(frenchHitsAllTime, contains(frenchHits2020s.first));
  });
}
