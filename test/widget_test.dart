import 'package:blackbook/src/app_theme_controller.dart';
import 'package:blackbook/src/schedule/schedule_models.dart';
import 'package:blackbook/src/schedule/schedule_page.dart';
import 'package:blackbook/src/schedule/schedule_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('loads the schedule home screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('第16周'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.textContaining('机器学习与智慧环境'), findsOneWidget);
  });

  testWidgets('matches probability and statistics courses as math', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(repository: _MathCourseScheduleRepository()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.textContaining('概率论与数理统计'), findsOneWidget);
    expect(find.byIcon(Icons.functions_outlined), findsOneWidget);
  });

  testWidgets('matches chemical engineering principle as chemistry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(
          repository: _SingleCourseScheduleRepository('化工原理（I）'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.textContaining('化工原理'), findsOneWidget);
    expect(find.byIcon(Icons.science_outlined), findsOneWidget);
  });

  testWidgets('applies dark colors to the schedule screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: SchedulePage(repository: _MemoryScheduleRepository()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF0B0C10));
  });

  testWidgets('chooses and persists a weekly conflict course', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(repository: _ConflictScheduleRepository()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.textContaining('有教室课程'), findsOneWidget);
    expect(find.textContaining('临时冲突课程'), findsNothing);

    await tester.tap(find.textContaining('有教室课程'));
    await tester.pumpAndSettle();
    expect(find.text('本周冲突课程'), findsOneWidget);
    await tester.ensureVisible(find.text('临时冲突课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('临时冲突课程'));
    await tester.pumpAndSettle();

    expect(find.textContaining('临时冲突课程'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().any(
        (key) =>
            key.startsWith('cup.imported.conflict_choice.191.') &&
            (preferences.getString(key)?.contains('A.01') ?? false),
      ),
      isTrue,
    );
  });

  testWidgets('shows out-of-week courses only in empty slots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePage(repository: _OutOfWeekScheduleRepository()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.textContaining('[非本周]'), findsOneWidget);
    expect(find.textContaining('未来非本周课程'), findsOneWidget);
    expect(find.textContaining('过去非本周课程'), findsNothing);
    expect(find.textContaining('被本周遮挡课程'), findsNothing);
  });

  testWidgets('opens the more dock from header', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themeController = AppThemeController();
    await tester.pumpWidget(
      AppThemeScope(
        controller: themeController,
        child: MaterialApp(
          home: SchedulePage(repository: _MemoryScheduleRepository()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('课表'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('小组件'), findsNothing);
    expect(find.text('清除导入'), findsNothing);
    expect(find.text('主题 自动'), findsOneWidget);

    await tester.tap(find.text('主题 自动'));
    await tester.pumpAndSettle();

    expect(themeController.preference, BlackbookThemePreference.light);
    expect(find.text('主题 亮色'), findsOneWidget);
  });

  testWidgets('opens hidden test dock from long pressing about', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.text('测试面板'), findsOneWidget);
    expect(find.text('测试灵动岛/上课提醒'), findsOneWidget);
    expect(find.text('小组件显示内容'), findsOneWidget);
  });

  testWidgets('opens account center from the more dock', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号管理'));
    await tester.pumpAndSettle();

    expect(find.text('账号管理'), findsOneWidget);
    expect(find.textContaining('中石大'), findsWidgets);
    expect(find.text('雨课堂'), findsNothing);
    expect(find.text('学习通'), findsNothing);
  });

  testWidgets('dismisses course detail dock when tapping outside', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.textContaining('机器学习与智慧环境'));
    await tester.pumpAndSettle();
    expect(find.text('授课教师'), findsOneWidget);

    await tester.tapAt(const Offset(20, 80));
    await tester.pumpAndSettle();

    expect(find.text('授课教师'), findsNothing);
  });

  testWidgets('keeps selected week when switching schedules', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ImportedScheduleStore();
    await store.save(
      semesterJson: _semesterJson(
        id: 211,
        name: '2026-2027-1',
        startDate: '2026-09-07',
        endDate: '2027-01-17',
      ),
      printDataJson: _printDataJson(
        semesterId: 211,
        courseName: '未来学期课程',
        weekIndexes: const [16],
      ),
      selectAfterSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('第16周'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('26-27-1'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(find.text('第16周'), findsOneWidget);
    expect(find.textContaining('未来学期课程'), findsOneWidget);
  });

  testWidgets('scrolls schedule choices horizontally in the more dock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ImportedScheduleStore();
    for (var index = 0; index < 8; index++) {
      final startYear = 2026 + index;
      await store.save(
        semesterJson: _semesterJson(
          id: 230 + index,
          name: '$startYear-${startYear + 1}-1',
          startDate: '$startYear-09-07',
          endDate: '${startYear + 1}-01-17',
        ),
        printDataJson: _printDataJson(
          semesterId: 230 + index,
          courseName: '横滑课表$index',
          weekIndexes: const [16],
        ),
        selectAfterSave: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final horizontalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScroll, findsOneWidget);

    final labels = [
      for (var startYear = 2033; startYear >= 2026; startYear--)
        '${startYear.toString().substring(2)}-'
            '${(startYear + 1).toString().substring(2)}-1',
    ];
    final rowTop = tester.getTopLeft(find.text(labels.first)).dy;
    for (final label in labels.skip(1)) {
      expect(tester.getTopLeft(find.text(label)).dy, rowTop);
    }

    final oldestSchedule = find.text('26-27-1');
    final beforeDragLeft = tester.getTopLeft(oldestSchedule).dx;
    await tester.drag(horizontalScroll, const Offset(-420, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(oldestSchedule).dx, lessThan(beforeDragLeft));
  });

  testWidgets('keeps selected week after adding a course', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上一周'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(find.text('第15周'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '课程名称'), '新增周保持课');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    expect(find.text('第15周'), findsOneWidget);
    expect(find.textContaining('新增周保持课'), findsOneWidget);
  });

  testWidgets('renames a saved schedule from schedule manager', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ImportedScheduleStore();
    await store.save(
      semesterJson: _semesterJson(
        id: 212,
        name: '2026-2027-2',
        startDate: '2027-03-01',
        endDate: '2027-06-20',
      ),
      printDataJson: _printDataJson(
        semesterId: 212,
        courseName: '可重命名课程',
        weekIndexes: const [16],
      ),
      selectAfterSave: false,
    );

    await tester.pumpWidget(
      MaterialApp(home: SchedulePage(repository: _MemoryScheduleRepository())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('重命名').first);
    await tester.pumpAndSettle();

    expect(find.text('重命名课表'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '测试课表');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();

    final renamed = (await store.loadAll()).singleWhere(
      (bundle) => bundle.semester.id == 212,
    );
    expect(renamed.semester.name, '测试课表');
  });

  test('stores a course with multiple time slots', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ImportedScheduleStore();
    await store.save(
      semesterJson: _semesterJson(
        id: 213,
        name: '2027-2028-1',
        startDate: '2027-09-06',
        endDate: '2028-01-16',
      ),
      printDataJson: _printDataJson(
        semesterId: 213,
        courseName: '底课',
        weekIndexes: const [16],
      ),
      selectAfterSave: true,
    );

    await store.upsertCourses(
      semesterId: 213,
      activities: [
        _localCourseActivity(weekday: 1, startUnit: 1, endUnit: 2),
        _localCourseActivity(
          weekday: 3,
          startUnit: 5,
          endUnit: 6,
          lessonCode: 'MT001#1',
        ),
      ],
    );

    final selected = await store.loadSelected();
    final created = selected!.schedule.activities.where(
      (activity) => activity.courseName == '多时间段课',
    );
    expect(created, hasLength(2));
    expect(created.map((activity) => activity.weekday), containsAll([1, 3]));
  });
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

Map<String, dynamic> _printDataJson({
  required int semesterId,
  required String courseName,
  required List<int> weekIndexes,
}) {
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
        'credits': 1,
        'semester': {'id': semesterId},
        'activities': [
          {
            'lessonId': 220001,
            'lessonCode': 'T.01',
            'courseCode': 'T',
            'courseName': courseName,
            'weeksStr': weekIndexes.join(','),
            'weekIndexes': weekIndexes,
            'weekday': 7,
            'startUnit': 3,
            'endUnit': 4,
            'startTime': '10:05',
            'endTime': '11:40',
            'room': '三教101',
            'building': '三教',
            'campus': '校本部',
            'teachers': ['测试教师'],
            'credits': 1,
            'lessonName': '',
          },
        ],
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
            {
              'indexNo': 2,
              'nameZh': '第2节',
              'startTime': 850,
              'endTime': 935,
              'dayPart': '上午',
              'segmentIndex': 1,
            },
            {
              'indexNo': 3,
              'nameZh': '第3节',
              'startTime': 1005,
              'endTime': 1050,
              'dayPart': '上午',
              'segmentIndex': 2,
            },
            {
              'indexNo': 4,
              'nameZh': '第4节',
              'startTime': 1055,
              'endTime': 1140,
              'dayPart': '上午',
              'segmentIndex': 2,
            },
          ],
        },
      },
    ],
  };
}

CourseActivity _localCourseActivity({
  required int weekday,
  required int startUnit,
  required int endUnit,
  String lessonCode = 'MT001',
}) {
  return CourseActivity(
    lessonId: -100,
    lessonCode: lessonCode,
    courseCode: 'MT001',
    courseName: '多时间段课',
    weeksText: '16',
    weekIndexes: const [16],
    weekday: weekday,
    startUnit: startUnit,
    endUnit: endUnit,
    startTime: '08:00',
    endTime: '09:35',
    room: '三教101',
    building: null,
    campus: null,
    teachers: const ['测试教师'],
    credits: 1,
    lessonName: '',
    lessonRemark: null,
  );
}

class _MemoryScheduleRepository implements ScheduleRepository {
  @override
  Future<ScheduleBundle> load() async {
    final semester = SemesterInfo(
      id: 191,
      name: '2025-2026-2',
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 6, 28),
      weekStartOnSunday: false,
    );

    return ScheduleBundle(
      semester: semester,
      schedule: StudentSchedule(
        student: const ScheduleStudent(
          id: 124179,
          name: '程锦涛',
          code: '2024010408',
          grade: '2024',
          department: '化学工程与环境学院',
          major: '环境工程',
          adminclass: '环工24-1班',
          credits: 34,
        ),
        courseUnits: const [],
        activities: const [
          CourseActivity(
            lessonId: 120581,
            lessonCode: '100307C004.01',
            courseCode: '100307C004',
            courseName: '机器学习与智慧环境',
            weeksText: '16',
            weekIndexes: [16],
            weekday: 7,
            startUnit: 3,
            endUnit: 4,
            startTime: '10:05',
            endTime: '11:40',
            room: '三教503机房',
            building: '三教',
            campus: '校本部',
            teachers: ['王一迪(2023880028,讲师)'],
            credits: 2.5,
            lessonName: '环工24-1班;环工24-2班',
            lessonRemark: null,
          ),
        ],
      ),
    );
  }
}

class _MathCourseScheduleRepository implements ScheduleRepository {
  @override
  Future<ScheduleBundle> load() async {
    final semester = SemesterInfo(
      id: 191,
      name: '2025-2026-2',
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 6, 28),
      weekStartOnSunday: false,
    );

    return ScheduleBundle(
      semester: semester,
      schedule: StudentSchedule(
        student: const ScheduleStudent(
          id: 124179,
          name: '程锦涛',
          code: '2024010408',
          grade: '2024',
          department: '化学工程与环境学院',
          major: '环境工程',
          adminclass: '环工24-1班',
          credits: 34,
        ),
        courseUnits: const [],
        activities: const [
          CourseActivity(
            lessonId: 120582,
            lessonCode: 'CS101.01',
            courseCode: 'CS101',
            courseName: '概率论与数理统计',
            weeksText: '16',
            weekIndexes: [16],
            weekday: 7,
            startUnit: 3,
            endUnit: 4,
            startTime: '10:05',
            endTime: '11:40',
            room: '三教110',
            building: '三教',
            campus: '校本部',
            teachers: ['孟得新'],
            credits: 3.5,
            lessonName: '',
            lessonRemark: null,
          ),
        ],
      ),
    );
  }
}

class _SingleCourseScheduleRepository implements ScheduleRepository {
  const _SingleCourseScheduleRepository(this.courseName);

  final String courseName;

  @override
  Future<ScheduleBundle> load() async {
    return ScheduleBundle.fromCupJson(
      semesterJson: _semesterJson(
        id: 191,
        name: '2025-2026-2',
        startDate: '2026-03-09',
        endDate: '2026-06-28',
      ),
      printDataJson: _printDataJson(
        semesterId: 191,
        courseName: courseName,
        weekIndexes: const [16],
      ),
    );
  }
}

class _ConflictScheduleRepository implements ScheduleRepository {
  @override
  Future<ScheduleBundle> load() async {
    final semester = SemesterInfo(
      id: 191,
      name: '2025-2026-2',
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 6, 28),
      weekStartOnSunday: false,
    );

    return ScheduleBundle(
      semester: semester,
      schedule: StudentSchedule(
        student: const ScheduleStudent(
          id: 124179,
          name: '程锦涛',
          code: '2024010408',
          grade: '2024',
          department: '化学工程与环境学院',
          major: '环境工程',
          adminclass: '环工24-1班',
          credits: 34,
        ),
        courseUnits: const [],
        activities: const [
          CourseActivity(
            lessonId: 1,
            lessonCode: 'A.01',
            courseCode: 'A',
            courseName: '临时冲突课程',
            weeksText: '16',
            weekIndexes: [16],
            weekday: 7,
            startUnit: 3,
            endUnit: 4,
            startTime: '10:05',
            endTime: '11:40',
            room: '具体上课时间请咨询任课教师',
            building: null,
            campus: null,
            teachers: ['张三'],
            credits: 1,
            lessonName: '',
            lessonRemark: null,
          ),
          CourseActivity(
            lessonId: 2,
            lessonCode: 'B.01',
            courseCode: 'B',
            courseName: '有教室课程',
            weeksText: '16',
            weekIndexes: [16],
            weekday: 7,
            startUnit: 3,
            endUnit: 4,
            startTime: '10:05',
            endTime: '11:40',
            room: '三教715',
            building: '三教',
            campus: '校本部',
            teachers: ['李四'],
            credits: 1,
            lessonName: '',
            lessonRemark: null,
          ),
        ],
      ),
    );
  }
}

class _OutOfWeekScheduleRepository implements ScheduleRepository {
  @override
  Future<ScheduleBundle> load() async {
    final semester = SemesterInfo(
      id: 191,
      name: '2025-2026-2',
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 6, 28),
      weekStartOnSunday: false,
    );

    return ScheduleBundle(
      semester: semester,
      schedule: StudentSchedule(
        student: const ScheduleStudent(
          id: 124179,
          name: '程锦涛',
          code: '2024010408',
          grade: '2024',
          department: '化学工程与环境学院',
          major: '环境工程',
          adminclass: '环工24-1班',
          credits: 34,
        ),
        courseUnits: const [],
        activities: const [
          CourseActivity(
            lessonId: 3,
            lessonCode: 'C.01',
            courseCode: 'C',
            courseName: '本周课程',
            weeksText: '16',
            weekIndexes: [16],
            weekday: 7,
            startUnit: 3,
            endUnit: 4,
            startTime: '10:05',
            endTime: '11:40',
            room: '三教101',
            building: '三教',
            campus: '校本部',
            teachers: ['王五'],
            credits: 1,
            lessonName: '',
            lessonRemark: null,
          ),
          CourseActivity(
            lessonId: 4,
            lessonCode: 'D.01',
            courseCode: 'D',
            courseName: '被本周遮挡课程',
            weeksText: '15',
            weekIndexes: [15],
            weekday: 7,
            startUnit: 3,
            endUnit: 4,
            startTime: '10:05',
            endTime: '11:40',
            room: '三教102',
            building: '三教',
            campus: '校本部',
            teachers: ['赵六'],
            credits: 1,
            lessonName: '',
            lessonRemark: null,
          ),
          CourseActivity(
            lessonId: 5,
            lessonCode: 'E.01',
            courseCode: 'E',
            courseName: '未来非本周课程',
            weeksText: '17',
            weekIndexes: [17],
            weekday: 7,
            startUnit: 7,
            endUnit: 8,
            startTime: '15:35',
            endTime: '17:10',
            room: '三教103',
            building: '三教',
            campus: '校本部',
            teachers: ['孙七'],
            credits: 1,
            lessonName: '',
            lessonRemark: null,
          ),
          CourseActivity(
            lessonId: 6,
            lessonCode: 'F.01',
            courseCode: 'F',
            courseName: '过去非本周课程',
            weeksText: '15',
            weekIndexes: [15],
            weekday: 7,
            startUnit: 9,
            endUnit: 10,
            startTime: '18:30',
            endTime: '20:05',
            room: '三教104',
            building: '三教',
            campus: '校本部',
            teachers: ['周八'],
            credits: 1,
            lessonName: '',
            lessonRemark: null,
          ),
        ],
      ),
    );
  }
}
