import 'dart:convert';

import 'package:blackbook/src/schedule/schedule_models.dart';
import 'package:blackbook/src/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'saves different semesters independently and selects latest import',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = ImportedScheduleStore();

      await store.save(
        semesterJson: _semesterJson(
          id: 191,
          name: '2025-2026-2',
          startDate: '2026-03-09',
          endDate: '2026-06-28',
        ),
        printDataJson: _printDataJson(semesterId: 191),
        selectAfterSave: true,
      );
      await store.save(
        semesterJson: _semesterJson(
          id: 211,
          name: '2026-2027-1',
          startDate: '2026-09-07',
          endDate: '2027-01-17',
        ),
        printDataJson: _printDataJson(semesterId: 211),
        selectAfterSave: true,
      );

      final bundles = await store.loadAll();
      expect(
        bundles.map((bundle) => bundle.semester.id),
        containsAllInOrder(<int>[211, 191]),
      );
      expect((await store.loadSelected())?.semester.id, 211);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('cup.imported.semester.ids'),
        containsAll(<String>['191', '211']),
      );
      expect(
        preferences.getString('cup.imported.semester.191'),
        isNot(equals(preferences.getString('cup.imported.semester.211'))),
      );
    },
  );

  test('migrates legacy single schedule into multi-semester list', () async {
    SharedPreferences.setMockInitialValues({
      'cup.imported.semester.json': jsonEncode(
        _semesterJson(
          id: 191,
          name: '2025-2026-2',
          startDate: '2026-03-09',
          endDate: '2026-06-28',
        ),
      ),
      'cup.imported.print_data.json': jsonEncode(
        _printDataJson(semesterId: 191),
      ),
    });
    final store = ImportedScheduleStore();

    await store.save(
      semesterJson: _semesterJson(
        id: 211,
        name: '2026-2027-1',
        startDate: '2026-09-07',
        endDate: '2027-01-17',
      ),
      printDataJson: _printDataJson(semesterId: 211),
      selectAfterSave: true,
    );

    final bundles = await store.loadAll();
    expect(
      bundles.map((bundle) => bundle.semester.id),
      containsAll(<int>[191, 211]),
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('cup.imported.semester.ids'),
      containsAll(<String>['191', '211']),
    );
  });

  test(
    'keeps source semester id and source fingerprint after local edits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = ImportedScheduleStore();

      final saved = await store.save(
        semesterJson: _semesterJson(
          id: 191,
          name: '2025-2026-2',
          startDate: '2026-03-09',
          endDate: '2026-06-28',
        ),
        printDataJson: _printDataJson(semesterId: 191),
        selectAfterSave: true,
      );
      final sourceFingerprint = await store.sourceFingerprintForSemester(191);

      final renamed = await store.renameSemester(191, '我改的名字');
      expect(renamed.semester.sourceSemesterId, 191);
      expect(await store.sourceFingerprintForSemester(191), sourceFingerprint);

      await store.upsertCourse(
        semesterId: saved.semester.id,
        activity: CourseActivity(
          lessonId: -1,
          lessonCode: 'local.01',
          courseCode: 'local',
          courseName: '本地课程',
          weeksText: '1',
          weekIndexes: const [1],
          weekday: 1,
          startUnit: 1,
          endUnit: 2,
          startTime: '08:00',
          endTime: '09:35',
          room: '三教101',
          building: null,
          campus: null,
          teachers: const ['测试教师'],
          credits: 1,
          lessonName: '',
          lessonRemark: null,
        ),
      );

      expect(await store.sourceFingerprintForSemester(191), sourceFingerprint);
      expect(await store.fingerprintForSemester(191), isNot(sourceFingerprint));
    },
  );
}

Map<String, dynamic> _semesterJson({
  required int id,
  required String name,
  required String startDate,
  required String endDate,
}) {
  return {
    'id': id,
    'nameZh': name,
    'name': name,
    'startDate': startDate,
    'endDate': endDate,
    'weekStartOnSunday': false,
  };
}

Map<String, dynamic> _printDataJson({required int semesterId}) {
  return {
    'studentTableVms': [
      {
        'id': 124179,
        'name': '程锦涛',
        'code': '2024010408',
        'grade': '2024',
        'department': '化学工程与环境学院',
        'major': '环境工程',
        'adminclass': '环工24-1班',
        'credits': 0,
        'semester': {'id': semesterId},
        'activities': <Map<String, dynamic>>[],
        'timeTableLayout': {
          'courseUnitList': [
            {
              'indexNo': 1,
              'nameZh': '第1节',
              'startTime': 800,
              'endTime': 845,
              'dayPart': '上午',
              'segmentIndex': 1,
            },
          ],
        },
      },
    ],
  };
}
