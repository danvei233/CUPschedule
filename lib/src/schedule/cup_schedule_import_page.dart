import 'package:flutter/material.dart';

import '../account/cup_account_service.dart';
import '../account/cup_api_client.dart';
import '../account/cup_auth_failure_handler.dart';
import '../app_palette.dart';
import '../common/stable_fingerprint.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

class CupScheduleImportPage extends StatefulWidget {
  const CupScheduleImportPage({super.key});

  @override
  State<CupScheduleImportPage> createState() => _CupScheduleImportPageState();
}

class _CupScheduleImportPageState extends State<CupScheduleImportPage> {
  final _accountService = const CupAccountService();
  final _scheduleStore = ImportedScheduleStore();
  late CupApiClient _client;

  CupCourseTableSession? _session;
  CupSchedulePayload? _preview;
  ScheduleBundle? _previewBundle;
  CupSemesterOption? _selectedSemester;
  var _loading = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _client = CupApiClient();
    _start();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final preview = _previewBundle;
    final palette = blackbookPalette(context);
    return Scaffold(
      backgroundColor: palette.pageBackground,
      floatingActionButton: preview == null
          ? null
          : FloatingActionButton.extended(
              tooltip: '确认导入',
              onPressed: _saving ? null : _confirmImport,
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text(
                '确认导入',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            _ImportHeader(
              loading: _loading || _saving,
              onBack: () => Navigator.of(context).pop(),
              onRefresh: _loading || _saving ? null : _restart,
            ),
            if (session != null)
              _SemesterStrip(
                semesters: session.semesters,
                selectedId: _selectedSemester?.id,
                enabled: !_loading && !_saving,
                onSelected: _loadPreview,
              ),
            Expanded(
              child: preview == null
                  ? _ImportEmptyState(
                      hasSemesters: session?.semesters.isNotEmpty ?? false,
                    )
                  : _ImportPreview(bundle: preview),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _session = null;
      _preview = null;
      _previewBundle = null;
      _selectedSemester = null;
    });

    try {
      final lease = await _accountService.acquireSession();
      _replaceClient(lease.client);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = lease.session;
        _loading = false;
      });
      _showNotice(
        '${lease.renewed ? '已续期' : '已复用'}会话，识别 ${lease.session.semesters.length} 个学期',
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      final action = await handleCupAuthFailure(context, error);
      if (action == CupAuthFailureAction.retry && mounted) {
        await _start();
      }
    }
  }

  Future<void> _restart() async {
    _replaceClient(CupApiClient());
    await _start();
  }

  Future<void> _loadPreview(CupSemesterOption semester) async {
    final session = _session;
    if (session == null || _loading || _saving) {
      return;
    }
    setState(() {
      _loading = true;
      _selectedSemester = semester;
      _preview = null;
      _previewBundle = null;
    });

    try {
      final payload = await _fetchScheduleWithRenew(session, semester);
      if (payload == null) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }
      if (payload.semester.id != semester.id) {
        throw StateError('返回课表学期和当前选择不一致');
      }
      final bundle = ScheduleBundle.fromCupJson(
        semesterJson: payload.semesterJson,
        printDataJson: payload.printDataJson,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = payload;
        _previewBundle = bundle;
        _loading = false;
      });
      _showNotice('已加载 ${semester.name}，请核对后确认导入');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      _showNotice('课表详情加载失败：${_cleanError(error)}', error: true);
    }
  }

  Future<void> _confirmImport() async {
    final payload = _preview;
    if (payload == null || _saving) {
      return;
    }
    final selected = await _scheduleStore.loadSelected();
    final shouldOverwriteSelected =
        (selected?.semester.sourceSemesterId ?? selected?.semester.id) ==
        payload.semester.id;
    if (!mounted) {
      return;
    }
    if (shouldOverwriteSelected && selected != null) {
      final existingFingerprint = await _scheduleStore.fingerprintForSemester(
        selected.semester.id,
      );
      final incomingFingerprint = schedulePayloadFingerprint(
        semesterJson: payload.semesterJson,
        printDataJson: payload.printDataJson,
      );
      if (!mounted) {
        return;
      }
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('覆盖已导入课表？'),
          content: Text(
            '${payload.semester.name} 已存在，继续会覆盖本地保存的数据。\n\n'
            '本地指纹：${existingFingerprint ?? '旧版本未记录'}\n'
            '新数据指纹：$incomingFingerprint\n'
            '状态：${existingFingerprint == incomingFingerprint ? '数据一致' : '数据不同'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (overwrite != true) {
        return;
      }
    }

    setState(() {
      _saving = true;
    });
    try {
      final semesterJson = shouldOverwriteSelected && selected != null
          ? <String, dynamic>{
              ...payload.semesterJson,
              'id': selected.semester.id,
              'nameZh': selected.semester.name,
              'name': selected.semester.name,
              'sourceSemesterId': payload.semester.id,
            }
          : <String, dynamic>{
              ...payload.semesterJson,
              'id': await _scheduleStore.nextLocalSemesterId(),
              'sourceSemesterId': payload.semester.id,
            };
      final bundle = await _scheduleStore.save(
        semesterJson: semesterJson,
        printDataJson: payload.printDataJson,
        selectAfterSave: true,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(bundle);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
      });
      _showNotice('保存失败：${_cleanError(error)}', error: true);
    }
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  Future<CupSchedulePayload?> _fetchScheduleWithRenew(
    CupCourseTableSession session,
    CupSemesterOption semester,
  ) async {
    try {
      return await _client.fetchSchedule(session, semester);
    } on Object catch (error) {
      if (error is! CupSessionExpiredException) {
        rethrow;
      }
      _showNotice('会话过期，自动续期后重试');
      while (mounted) {
        try {
          final lease = await _accountService.refreshSession();
          _replaceClient(lease.client);
          setState(() {
            _session = lease.session;
          });
          return _client.fetchSchedule(lease.session, semester);
        } on Object catch (renewalError) {
          if (!mounted) {
            return null;
          }
          final action = await handleCupAuthFailure(context, renewalError);
          if (action != CupAuthFailureAction.retry) {
            return null;
          }
        }
      }
      return null;
    }
  }

  void _replaceClient(CupApiClient nextClient) {
    if (identical(_client, nextClient)) {
      return;
    }
    _client.close();
    _client = nextClient;
  }

  void _showNotice(String text, {bool error = false}) {
    if (!mounted) {
      return;
    }
    final palette = blackbookPalette(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: (error ? palette.danger : palette.primary).withValues(
          alpha: 0.86,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _ImportHeader extends StatelessWidget {
  const _ImportHeader({
    required this.loading,
    required this.onBack,
    required this.onRefresh,
  });

  final bool loading;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            color: palette.ink,
            iconSize: 30,
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              '导入中石大课表',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: palette.ink,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          IconButton(
            tooltip: '重新执行导入流程',
            onPressed: onRefresh,
            color: palette.ink,
            iconSize: 28,
            icon: loading
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _SemesterStrip extends StatelessWidget {
  const _SemesterStrip({
    required this.semesters,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final List<CupSemesterOption> semesters;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<CupSemesterOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: semesters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final semester = semesters[index];
          final selected = semester.id == selectedId;
          return _SemesterPill(
            semester: semester,
            selected: selected,
            enabled: enabled,
            onTap: () => onSelected(semester),
          );
        },
      ),
    );
  }
}

class _SemesterPill extends StatelessWidget {
  const _SemesterPill({
    required this.semester,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final CupSemesterOption semester;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 106,
          height: 34,
          decoration: BoxDecoration(
            color: selected ? palette.primary : palette.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? palette.primary : palette.divider,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            semester.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: selected ? palette.onPrimary : palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportEmptyState extends StatelessWidget {
  const _ImportEmptyState({required this.hasSemesters});

  final bool hasSemesters;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSemesters ? Icons.touch_app_outlined : Icons.cloud_sync,
              size: 40,
              color: palette.primary,
            ),
            const SizedBox(height: 10),
            Text(
              hasSemesters ? '点上方学期查看课表详情' : '自动通过中石大 API 建立会话',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasSemesters ? '确认无误后用右下角按钮导入。' : '正在读取账号中心并连接中石大 API。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.subtle,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.bundle});

  final ScheduleBundle bundle;

  @override
  Widget build(BuildContext context) {
    final student = bundle.schedule.student;
    final uniqueCourses = _uniqueCourses(bundle.schedule.activities);
    final courses = uniqueCourses.length;
    final fingerprint = stableJsonFingerprint({
      'semester': bundle.semester.toJson(),
      'activities': bundle.schedule.activities.map(_activityFingerprintData),
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      children: [
        _PreviewHeader(
          semester: bundle.semester,
          student: student,
          courseCount: courses,
          activityCount: bundle.schedule.activities.length,
          fingerprint: fingerprint,
        ),
        const SizedBox(height: 4),
        _PreviewSection(
          title: '学生信息',
          gridRows: [
            _PreviewInfoItem(Icons.person_outline, student.name, '姓名'),
            _PreviewInfoItem(Icons.badge_outlined, student.code, '学号'),
            _PreviewInfoItem(
              Icons.apartment_outlined,
              student.department,
              '学院',
            ),
            _PreviewInfoItem(Icons.school_outlined, student.major, '专业'),
            _PreviewInfoItem(Icons.groups_outlined, student.adminclass, '班级'),
          ],
        ),
        const SizedBox(height: 4),
        _PreviewSection(
          title: '课程概览',
          trailing: '共 $courses 门课',
          courseRows: uniqueCourses
              .take(14)
              .map(
                (activity) => _PreviewRow(
                  Icons.menu_book_outlined,
                  activity.courseName,
                  '${activity.credits.toStringAsFixed(1)} 学分 · '
                  '${activity.programType.label}',
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  List<CourseActivity> _uniqueCourses(List<CourseActivity> activities) {
    return activities
        .fold<Map<String, CourseActivity>>(
          {},
          (map, activity) => map
            ..putIfAbsent(
              '${activity.programType.storageValue}|${activity.courseCode}',
              () => activity,
            ),
        )
        .values
        .toList()
      ..sort((a, b) {
        final creditCompare = b.credits.compareTo(a.credits);
        if (creditCompare != 0) {
          return creditCompare;
        }
        return a.courseName.compareTo(b.courseName);
      });
  }

  Map<String, Object?> _activityFingerprintData(CourseActivity activity) {
    return {
      'lessonId': activity.lessonId,
      'lessonCode': activity.lessonCode,
      'courseCode': activity.courseCode,
      'courseName': activity.courseName,
      'weeksText': activity.weeksText,
      'weekIndexes': activity.weekIndexes,
      'weekday': activity.weekday,
      'startUnit': activity.startUnit,
      'endUnit': activity.endUnit,
      'room': activity.room,
      'teachers': activity.teachers,
      'programType': activity.programType.storageValue,
    };
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.semester,
    required this.student,
    required this.courseCount,
    required this.activityCount,
    required this.fingerprint,
  });

  final SemesterInfo semester;
  final ScheduleStudent student;
  final int courseCount;
  final int activityCount;
  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          semester.name,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontSize: 23,
            height: 1,
            fontWeight: FontWeight.w900,
            color: palette.primary,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_dateText(semester.startDate)} - ${_dateText(semester.endDate)}  ·  '
          '${semester.totalWeeks}周',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: palette.subtle,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.68,
          children: [
            _MetricCard(
              icon: Icons.menu_book_outlined,
              value: '$courseCount',
              label: '门课',
              color: const Color(0xFF6A5BFF),
            ),
            _MetricCard(
              icon: Icons.format_list_bulleted,
              value: '$activityCount',
              label: '条安排',
              color: const Color(0xFF1D8FD6),
            ),
            _MetricCard(
              icon: Icons.grade_outlined,
              value: student.credits.toStringAsFixed(1),
              label: '学分',
              color: const Color(0xFFE4863E),
            ),
            _MetricCard(
              icon: Icons.fingerprint,
              value: fingerprint.substring(0, 8),
              label: '指纹',
              color: const Color(0xFF20A990),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.subtle,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.title,
    this.trailing,
    this.gridRows = const [],
    this.courseRows = const [],
  });

  final String title;
  final String? trailing;
  final List<_PreviewInfoItem> gridRows;
  final List<_PreviewRow> courseRows;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: palette.ink,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    trailing!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (gridRows.isNotEmpty)
            _StudentInfoGrid(items: gridRows)
          else
            _CoursePreviewList(rows: courseRows),
        ],
      ),
    );
  }
}

class _StudentInfoGrid extends StatelessWidget {
  const _StudentInfoGrid({required this.items});

  final List<_PreviewInfoItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index += 2)
            DecoratedBox(
              decoration: BoxDecoration(
                border: index + 2 < items.length
                    ? Border(bottom: BorderSide(color: palette.weakDivider))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(child: _StudentInfoTile(item: items[index])),
                  if (index + 1 < items.length) ...[
                    SizedBox(
                      height: 40,
                      child: VerticalDivider(color: palette.weakDivider),
                    ),
                    Expanded(child: _StudentInfoTile(item: items[index + 1])),
                  ] else
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StudentInfoTile extends StatelessWidget {
  const _StudentInfoTile({required this.item});

  final _PreviewInfoItem item;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      child: Row(
        children: [
          Icon(item.icon, color: palette.primary, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.subtle,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoursePreviewList extends StatelessWidget {
  const _CoursePreviewList({required this.rows});

  final List<_PreviewRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: palette.weakDivider, width: 0.8),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(row.icon, size: 17, color: palette.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.ink,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        row.trailing,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewRow {
  const _PreviewRow(this.icon, this.text, this.trailing);

  final IconData icon;
  final String text;
  final String trailing;
}

class _PreviewInfoItem {
  const _PreviewInfoItem(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;
}

String _dateText(DateTime value) =>
    '${value.month}/${value.day}/${value.year % 100}';
