import 'dart:io';

import 'package:blackbook/src/account/cup_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses CUP course table session from saved HTML', () async {
    final html = await File(
      'docs/research/cup_schedule/cup-course-table-page.html',
    ).readAsString();

    final client = CupApiClient();
    addTearDown(client.close);

    final session = client.parseCourseTableSessionForTest(html);

    expect(session.personId, 3386715);
    expect(session.bizTypeId, 2);
    expect(session.currentSemesterId, 191);
    expect(
      session.semesters.map((item) => item.id),
      containsAll([91, 191, 211]),
    );
    expect(session.semesters.first.name, '2026-2027-1');
  });
}
