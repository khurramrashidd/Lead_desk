// Unit tests for helpers that don't need Firebase.
// Run with:  flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:lead_desk/utils/ist.dart';
import 'package:lead_desk/widgets/lead_widgets.dart';

void main() {
  test('IST formatting does not depend on the device time zone', () {
    final utc = DateTime.utc(2026, 10, 16, 8, 30); // = 2:00 PM in India
    expect(Ist.full(utc), 'Fri, 16 Oct · 2:00 PM IST');
    expect(Ist.time(utc), '2:00 PM');
  });

  test('IST date rolls over correctly after 6:30 PM UTC', () {
    final utc = DateTime.utc(2026, 10, 16, 19, 0); // = 12:30 AM next day in India
    expect(Ist.full(utc), 'Sat, 17 Oct · 12:30 AM IST');
  });

  test('initials work for English and Devanagari names', () {
    expect(initialsOf('Rahul Patil'), 'RP');
    expect(initialsOf('sneha'), 'S');
    expect(initialsOf('राहुल पाटील'), 'रप');
    expect(initialsOf(''), '?');
    expect(initialsOf(null), '?');
  });

  test('relative time labels', () {
    expect(Ist.relative(null), 'now');
    expect(Ist.relative(DateTime.now().subtract(const Duration(minutes: 5))), '5 min ago');
    expect(Ist.relative(DateTime.now().subtract(const Duration(hours: 3))), '3 h ago');
  });
}
