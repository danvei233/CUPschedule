class SemesterInfo {
  const SemesterInfo({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.weekStartOnSunday,
    this.sourceSemesterId,
  });

  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool weekStartOnSunday;
  final int? sourceSemesterId;

  SemesterInfo copyWith({
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    bool? weekStartOnSunday,
    int? sourceSemesterId,
  }) {
    return SemesterInfo(
      id: id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      weekStartOnSunday: weekStartOnSunday ?? this.weekStartOnSunday,
      sourceSemesterId: sourceSemesterId ?? this.sourceSemesterId,
    );
  }

  factory SemesterInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    return SemesterInfo(
      id: id,
      name: (json['nameZh'] ?? json['name'] ?? '') as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      weekStartOnSunday: json['weekStartOnSunday'] as bool? ?? false,
      sourceSemesterId:
          (json['sourceSemesterId'] as num?)?.toInt() ?? (id > 0 ? id : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nameZh': name,
      'name': name,
      'startDate': _dateText(startDate),
      'endDate': _dateText(endDate),
      'weekStartOnSunday': weekStartOnSunday,
      if (sourceSemesterId != null) 'sourceSemesterId': sourceSemesterId,
    };
  }

  int get totalWeeks {
    final days = endDate.difference(startDate).inDays;
    return (days / 7).ceil();
  }

  DateTime dateFor({required int weekIndex, required int weekday}) {
    final weekdayOffset = weekStartOnSunday ? weekday % 7 : weekday - 1;
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day + ((weekIndex - 1) * 7) + weekdayOffset,
    );
  }

  int weekIndexFor(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized.isBefore(startDate)) {
      return 1;
    }
    final diff = normalized.difference(startDate).inDays;
    final week = (diff ~/ 7) + 1;
    if (week < 1) {
      return 1;
    }
    if (week > totalWeeks) {
      return totalWeeks;
    }
    return week;
  }

  static String _dateText(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class StudentSchedule {
  const StudentSchedule({
    required this.student,
    required this.activities,
    required this.courseUnits,
  });

  final ScheduleStudent student;
  final List<CourseActivity> activities;
  final List<CourseUnit> courseUnits;

  StudentSchedule copyWith({
    ScheduleStudent? student,
    List<CourseActivity>? activities,
    List<CourseUnit>? courseUnits,
  }) {
    return StudentSchedule(
      student: student ?? this.student,
      activities: activities ?? this.activities,
      courseUnits: courseUnits ?? this.courseUnits,
    );
  }

  factory StudentSchedule.fromCupPrintData(Map<String, dynamic> json) {
    final studentTableVms = (json['studentTableVms'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final table = studentTableVms.first;
    final activities =
        studentTableVms.indexed
            .expand(
              (entry) => (entry.$2['activities'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>()
                  .map((json) {
                    final activity = CourseActivity.fromJson(json);
                    if (json.containsKey('programType')) {
                      return activity;
                    }
                    return activity.copyWith(
                      programType: entry.$1 == 0
                          ? CourseProgramType.primary
                          : CourseProgramType.minor,
                    );
                  }),
            )
            .toList()
          ..sort(CourseActivity.compareByTime);
    final courseUnitsByIndex = <int, CourseUnit>{};
    for (final studentTable in studentTableVms) {
      final layout = studentTable['timeTableLayout'] as Map<String, dynamic>?;
      final rawUnits = layout?['courseUnitList'] as List<dynamic>? ?? const [];
      for (final rawUnit in rawUnits.cast<Map<String, dynamic>>()) {
        final unit = CourseUnit.fromJson(rawUnit);
        courseUnitsByIndex.putIfAbsent(unit.indexNo, () => unit);
      }
    }
    final courseUnits = courseUnitsByIndex.values.toList()
      ..sort((a, b) => a.indexNo.compareTo(b.indexNo));

    return StudentSchedule(
      student: ScheduleStudent.fromJson(table),
      activities: activities,
      courseUnits: courseUnits,
    );
  }

  List<CourseActivity> activitiesForWeek(int weekIndex) {
    return activities
        .where((activity) => activity.weekIndexes.contains(weekIndex))
        .toList()
      ..sort(CourseActivity.compareByTime);
  }

  List<CourseActivity> activitiesForDate(SemesterInfo semester, DateTime date) {
    final weekIndex = semester.weekIndexFor(date);
    final weekday = date.weekday;
    return activities
        .where(
          (activity) =>
              activity.weekday == weekday &&
              activity.weekIndexes.contains(weekIndex),
        )
        .toList()
      ..sort(CourseActivity.compareByTime);
  }

  Map<String, dynamic> toCupPrintData(int semesterId) {
    return {
      'studentTableVms': [
        {
          ...student.toJson(),
          'semester': {'id': semesterId},
          'semesterId': semesterId,
          'activities': activities
              .map((activity) => activity.toJson())
              .toList(),
          'timeTableLayout': {
            'courseUnitList': courseUnits.map((unit) => unit.toJson()).toList(),
          },
        },
      ],
    };
  }
}

class ScheduleStudent {
  const ScheduleStudent({
    required this.id,
    required this.name,
    required this.code,
    required this.grade,
    required this.department,
    required this.major,
    required this.adminclass,
    required this.credits,
  });

  final int id;
  final String name;
  final String code;
  final String grade;
  final String department;
  final String major;
  final String adminclass;
  final double credits;

  factory ScheduleStudent.fromJson(Map<String, dynamic> json) {
    return ScheduleStudent(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      grade: json['grade'] as String? ?? '',
      department: json['department'] as String? ?? '',
      major: json['major'] as String? ?? '',
      adminclass: json['adminclass'] as String? ?? '',
      credits: (json['credits'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'grade': grade,
      'department': department,
      'major': major,
      'adminclass': adminclass,
      'credits': credits,
    };
  }
}

enum CourseProgramType {
  primary('primary', '主修'),
  minor('minor', '辅修');

  const CourseProgramType(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static CourseProgramType fromJson(Object? value) {
    return values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => primary,
    );
  }
}

class CourseActivity {
  const CourseActivity({
    required this.lessonId,
    required this.lessonCode,
    required this.courseCode,
    required this.courseName,
    required this.weeksText,
    required this.weekIndexes,
    required this.weekday,
    required this.startUnit,
    required this.endUnit,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.building,
    required this.campus,
    required this.teachers,
    required this.credits,
    required this.lessonName,
    required this.lessonRemark,
    this.iconKey,
    this.colorKey,
    this.courseNature = '必修',
    this.programType = CourseProgramType.primary,
  });

  final int lessonId;
  final String lessonCode;
  final String courseCode;
  final String courseName;
  final String weeksText;
  final List<int> weekIndexes;
  final int weekday;
  final int startUnit;
  final int endUnit;
  final String startTime;
  final String endTime;
  final String room;
  final String? building;
  final String? campus;
  final List<String> teachers;
  final double credits;
  final String lessonName;
  final String? lessonRemark;
  final String? iconKey;
  final String? colorKey;
  final String courseNature;
  final CourseProgramType programType;

  factory CourseActivity.fromJson(Map<String, dynamic> json) {
    return CourseActivity(
      lessonId: json['lessonId'] as int,
      lessonCode: json['lessonCode'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      weeksText: json['weeksStr'] as String? ?? '',
      weekIndexes:
          (json['weekIndexes'] as List<dynamic>? ?? const [])
              .map((value) => value as int)
              .toList()
            ..sort(),
      weekday: json['weekday'] as int,
      startUnit: json['startUnit'] as int,
      endUnit: json['endUnit'] as int,
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      room: json['room'] as String? ?? '',
      building: json['building'] as String?,
      campus: json['campus'] as String?,
      teachers: (json['teachers'] as List<dynamic>? ?? const [])
          .map((value) => value as String)
          .toList(),
      credits: (json['credits'] as num?)?.toDouble() ?? 0,
      lessonName: json['lessonName'] as String? ?? '',
      lessonRemark: json['lessonRemark'] as String?,
      iconKey: json['iconKey'] as String?,
      colorKey: json['colorKey'] as String?,
      courseNature: _courseNatureFromJson(json),
      programType: CourseProgramType.fromJson(json['programType']),
    );
  }

  CourseActivity copyWith({
    int? lessonId,
    String? lessonCode,
    String? courseCode,
    String? courseName,
    String? weeksText,
    List<int>? weekIndexes,
    int? weekday,
    int? startUnit,
    int? endUnit,
    String? startTime,
    String? endTime,
    String? room,
    String? building,
    String? campus,
    List<String>? teachers,
    double? credits,
    String? lessonName,
    String? lessonRemark,
    String? iconKey,
    String? colorKey,
    String? courseNature,
    CourseProgramType? programType,
    bool clearIconKey = false,
    bool clearColorKey = false,
  }) {
    return CourseActivity(
      lessonId: lessonId ?? this.lessonId,
      lessonCode: lessonCode ?? this.lessonCode,
      courseCode: courseCode ?? this.courseCode,
      courseName: courseName ?? this.courseName,
      weeksText: weeksText ?? this.weeksText,
      weekIndexes: weekIndexes ?? this.weekIndexes,
      weekday: weekday ?? this.weekday,
      startUnit: startUnit ?? this.startUnit,
      endUnit: endUnit ?? this.endUnit,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
      building: building ?? this.building,
      campus: campus ?? this.campus,
      teachers: teachers ?? this.teachers,
      credits: credits ?? this.credits,
      lessonName: lessonName ?? this.lessonName,
      lessonRemark: lessonRemark ?? this.lessonRemark,
      iconKey: clearIconKey ? null : iconKey ?? this.iconKey,
      colorKey: clearColorKey ? null : colorKey ?? this.colorKey,
      courseNature: courseNature ?? this.courseNature,
      programType: programType ?? this.programType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lessonId': lessonId,
      'lessonCode': lessonCode,
      'courseCode': courseCode,
      'courseName': courseName,
      'weeksStr': weeksText,
      'weekIndexes': weekIndexes,
      'weekday': weekday,
      'startUnit': startUnit,
      'endUnit': endUnit,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
      'building': building,
      'campus': campus,
      'teachers': teachers,
      'credits': credits,
      'lessonName': lessonName,
      'lessonRemark': lessonRemark,
      if (iconKey != null) 'iconKey': iconKey,
      if (colorKey != null) 'colorKey': colorKey,
      'courseNature': courseNature,
      'programType': programType.storageValue,
    };
  }

  static int compareByTime(CourseActivity a, CourseActivity b) {
    final weekdayCompare = a.weekday.compareTo(b.weekday);
    if (weekdayCompare != 0) {
      return weekdayCompare;
    }
    final unitCompare = a.startUnit.compareTo(b.startUnit);
    if (unitCompare != 0) {
      return unitCompare;
    }
    return a.courseName.compareTo(b.courseName);
  }

  List<DateTime> datesInSemester(SemesterInfo semester) {
    return weekIndexes
        .map(
          (weekIndex) =>
              semester.dateFor(weekIndex: weekIndex, weekday: weekday),
        )
        .toList();
  }

  String get unitText {
    if (startUnit == endUnit) {
      return '第$startUnit节';
    }
    return '第$startUnit-$endUnit节';
  }

  String get teacherText => teachers.isEmpty ? '教师未公布' : teachers.join(' / ');

  String get placeText {
    final parts = <String>[
      if (campus != null && campus!.isNotEmpty) campus!,
      if (room.isNotEmpty) room,
    ];
    return parts.isEmpty ? '地点未公布' : parts.join(' ');
  }

  static String _courseNatureFromJson(Map<String, dynamic> json) {
    final direct = json['courseNature'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    final candidates = <Object?>[
      json['compulsorysStr'],
      json['lessonKindText'],
      json['lessonKindZh'],
      json['courseProperty'],
    ];
    for (final candidate in candidates) {
      final text = _localizedName(candidate);
      if (text == null || text.isEmpty) {
        continue;
      }
      if (text.contains('选')) {
        return '选修';
      }
      if (text.contains('必')) {
        return '必修';
      }
    }
    return '必修';
  }

  static String? _localizedName(Object? value) {
    if (value is String) {
      return value.trim();
    }
    if (value is Map<dynamic, dynamic>) {
      final raw = value['nameZh'] ?? value['name'];
      if (raw is String) {
        return raw.trim();
      }
    }
    return null;
  }
}

class CourseUnit {
  const CourseUnit({
    required this.indexNo,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.dayPart,
    required this.segmentIndex,
  });

  final int indexNo;
  final String name;
  final int startTime;
  final int endTime;
  final String dayPart;
  final int segmentIndex;

  factory CourseUnit.fromJson(Map<String, dynamic> json) {
    return CourseUnit(
      indexNo: json['indexNo'] as int,
      name: json['nameZh'] as String? ?? '',
      startTime: json['startTime'] as int,
      endTime: json['endTime'] as int,
      dayPart: json['dayPart'] as String? ?? '',
      segmentIndex: json['segmentIndex'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'indexNo': indexNo,
      'nameZh': name,
      'startTime': startTime,
      'endTime': endTime,
      'dayPart': dayPart,
      'segmentIndex': segmentIndex,
    };
  }

  String get startTimeText => _formatClock(startTime);

  String get endTimeText => _formatClock(endTime);

  static String _formatClock(int value) {
    final hour = value ~/ 100;
    final minute = value % 100;
    return '$hour:${minute.toString().padLeft(2, '0')}';
  }
}
