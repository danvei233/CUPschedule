import 'package:blackbook/src/schedule/schedule_models.dart';
import 'package:blackbook/src/schedule/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps CUP week and weekday to calendar date', () {
    final semester = SemesterInfo(
      id: 191,
      name: '2025-2026-2',
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 7, 10),
      weekStartOnSunday: false,
    );

    expect(semester.dateFor(weekIndex: 1, weekday: 1), DateTime(2026, 3, 9));
    expect(semester.dateFor(weekIndex: 16, weekday: 7), DateTime(2026, 6, 28));
    expect(semester.weekIndexFor(DateTime(2026, 6, 28)), 16);
    expect(semester.weekIndexFor(DateTime(2026, 2, 28)), 1);
    expect(semester.weekIndexFor(DateTime(2026, 8, 1)), semester.totalWeeks);
  });

  test('rejects CUP schedule data from a different semester', () {
    final semesterJson = {
      'id': 211,
      'nameZh': '2026-2027-2',
      'startDate': '2027-03-01',
      'endDate': '2027-07-09',
      'weekStartOnSunday': false,
    };
    final printDataJson = {
      'studentTableVms': [
        {
          'id': 1,
          'name': '学生',
          'code': '2024010408',
          'activities': <Map<String, dynamic>>[],
          'lessonSearchVms': [
            {
              'semester': {'id': 191, 'nameZh': '2025-2026-2'},
            },
          ],
          'timeTableLayout': {'courseUnitList': <Map<String, dynamic>>[]},
        },
      ],
    };

    expect(
      () => ScheduleBundle.fromCupJson(
        semesterJson: semesterJson,
        printDataJson: printDataJson,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('不是 2026-2027-2(211)'),
        ),
      ),
    );
  });

  test('keeps local course icon and nature in JSON', () {
    final activity = CourseActivity.fromJson({
      'lessonId': 1,
      'lessonCode': 'A.01',
      'courseCode': 'A',
      'courseName': '本地课',
      'weeksStr': '1-2',
      'weekIndexes': [1, 2],
      'weekday': 1,
      'startUnit': 1,
      'endUnit': 2,
      'startTime': '08:00',
      'endTime': '09:35',
      'room': '三教101',
      'building': null,
      'campus': null,
      'teachers': ['测试教师'],
      'credits': 1,
      'lessonName': '',
      'lessonRemark': null,
      'iconKey': 'computer',
      'colorKey': 'chemistry',
      'courseNature': '选修',
    });

    expect(activity.iconKey, 'computer');
    expect(activity.colorKey, 'chemistry');
    expect(activity.courseNature, '选修');
    expect(activity.programType, CourseProgramType.primary);
    expect(activity.toJson()['iconKey'], 'computer');
    expect(activity.toJson()['colorKey'], 'chemistry');
    expect(activity.toJson()['courseNature'], '选修');
    expect(activity.toJson()['programType'], 'primary');
    expect(activity.copyWith(clearIconKey: true).iconKey, isNull);
    expect(activity.copyWith(clearColorKey: true).colorKey, isNull);
  });

  test('merges activities from primary and minor course tables', () {
    final schedule = StudentSchedule.fromCupPrintData({
      'studentTableVms': [
        _studentTable(
          activities: [_activityJson(name: '主修课程', weekday: 2)],
          courseUnits: [_courseUnitJson(1), _courseUnitJson(2)],
        ),
        _studentTable(
          activities: [_activityJson(name: '辅修课程', weekday: 1)],
          courseUnits: [_courseUnitJson(1), _courseUnitJson(2)],
        ),
      ],
    });

    expect(schedule.activities.map((activity) => activity.courseName), [
      '辅修课程',
      '主修课程',
    ]);
    expect(schedule.activities.map((activity) => activity.programType), [
      CourseProgramType.minor,
      CourseProgramType.primary,
    ]);
    expect(schedule.courseUnits.map((unit) => unit.indexNo), [1, 2]);
  });

  test('round-trips a minor course program type', () {
    final activity = CourseActivity.fromJson({
      ..._activityJson(name: '辅修课程', weekday: 1),
      'programType': 'minor',
    });

    expect(activity.programType, CourseProgramType.minor);
    expect(activity.toJson()['programType'], 'minor');
    expect(
      activity.copyWith(programType: CourseProgramType.primary).programType,
      CourseProgramType.primary,
    );
  });
}

Map<String, dynamic> _studentTable({
  required List<Map<String, dynamic>> activities,
  required List<Map<String, dynamic>> courseUnits,
}) {
  return {
    'id': 1,
    'name': '测试学生',
    'code': '2023000000',
    'activities': activities,
    'timeTableLayout': {'courseUnitList': courseUnits},
  };
}

Map<String, dynamic> _activityJson({
  required String name,
  required int weekday,
}) {
  return {
    'lessonId': weekday,
    'courseName': name,
    'weekIndexes': [1],
    'weekday': weekday,
    'startUnit': 1,
    'endUnit': 2,
  };
}

Map<String, dynamic> _courseUnitJson(int index) {
  return {
    'indexNo': index,
    'nameZh': '第$index节',
    'startTime': index == 1 ? 800 : 850,
    'endTime': index == 1 ? 845 : 935,
    'dayPart': '上午',
    'segmentIndex': 0,
  };
}
