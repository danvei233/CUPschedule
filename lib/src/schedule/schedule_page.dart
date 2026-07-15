import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_center_dialog.dart';
import '../account/cup_account_service.dart';
import '../account/cup_api_client.dart';
import '../account/cup_auth_failure_handler.dart';
import '../app_palette.dart';
import '../app_theme_controller.dart';
import 'cup_schedule_import_page.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

Color _accentBackgroundFor(BuildContext context, _CourseAccent accent) {
  if (Theme.of(context).brightness != Brightness.dark) {
    return accent.background;
  }
  return Color.alphaBlend(
    accent.foreground.withValues(alpha: 0.24),
    blackbookPalette(context).surfaceAlt,
  );
}

Color _accentForegroundFor(BuildContext context, _CourseAccent accent) {
  if (Theme.of(context).brightness != Brightness.dark) {
    return accent.foreground;
  }
  return Color.alphaBlend(
    accent.foreground.withValues(alpha: 0.36),
    Colors.white,
  );
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    this.repository = const CupScheduleRepository(),
  });

  final ScheduleRepository repository;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _store = ImportedScheduleStore();
  late Future<ScheduleBundle> _bundleFuture;
  ScheduleBundle? _bundle;
  List<ScheduleBundle> _availableBundles = const [];
  Map<String, String> _conflictChoices = const {};
  int? _selectedWeek;
  PageController? _weekPageController;
  int? _weekPageControllerSemesterId;
  late final ValueNotifier<int> _selectedWeekNotifier;
  _WeekLayoutCache? _weekLayoutCache;
  int? _weekLayoutSemesterId;
  int? _weekLayoutActivitiesIdentity;
  int? _weekLayoutChoiceFingerprint;
  int _weekLayoutGeneration = 0;
  int _weekLayoutWarmupCenterWeek = 1;
  bool _weekLayoutWarmupPending = false;
  Timer? _weekLayoutWarmupTimer;
  Timer? _bundlePersistTimer;
  ScheduleBundle? _pendingPersistBundle;
  int _bundlePersistGeneration = 0;
  final _accountService = const CupAccountService();
  bool _syncingSchedule = false;
  Object? _handledLoadError;
  bool _handlingLoadError = false;

  @override
  void initState() {
    super.initState();
    _selectedWeekNotifier = ValueNotifier<int>(1);
    _bundleFuture = _loadBundle();
  }

  @override
  void dispose() {
    _weekLayoutWarmupTimer?.cancel();
    _bundlePersistTimer?.cancel();
    final pendingPersistBundle = _pendingPersistBundle;
    if (pendingPersistBundle != null) {
      unawaited(_store.saveBundle(pendingPersistBundle, selectAfterSave: true));
    }
    _weekPageController?.dispose();
    _selectedWeekNotifier.dispose();
    super.dispose();
  }

  Future<ScheduleBundle> _loadBundle() async {
    final bundle = await widget.repository.load();
    final importedBundles = await _loadImportedBundles();
    _bundle = bundle;
    _availableBundles = importedBundles;
    _conflictChoices = await _store.loadConflictChoices(bundle.semester.id);
    _setSelectedWeekValue(
      _clampWeek(
        _selectedWeek ?? _defaultWeek(bundle.semester),
        bundle.semester,
      ),
    );
    return bundle;
  }

  Future<List<ScheduleBundle>> _loadImportedBundles() async {
    try {
      return _store.loadAll();
    } on Object {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ScheduleBundle>(
      future: _bundleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          final palette = blackbookPalette(context);
          return Scaffold(
            backgroundColor: palette.pageBackground,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          final palette = blackbookPalette(context);
          final error = snapshot.error ?? StateError('未知错误');
          if (!identical(_handledLoadError, error)) {
            _handledLoadError = error;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleInitialLoadFailure(error);
            });
          }
          return Scaffold(
            backgroundColor: palette.pageBackground,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '课表暂时无法加载',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _handlingLoadError ? null : _retryInitialLoad,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final bundle = _bundle ?? snapshot.data!;
        final week = _selectedWeek ?? _defaultWeek(bundle.semester);
        final pageController = _pageControllerFor(bundle.semester.id, week);
        final weekLayouts = _layoutCacheFor(bundle);
        _prepareWeekLayouts(weekLayouts, week);
        final scheduleBundles = _scheduleBundlesForDisplay(bundle);
        final palette = blackbookPalette(context);

        return Scaffold(
          backgroundColor: palette.pageBackground,
          body: SafeArea(
            child: Column(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: _selectedWeekNotifier,
                  builder: (context, selectedWeek, _) {
                    final headerWeek = _clampWeek(
                      selectedWeek,
                      bundle.semester,
                    );
                    return _ScheduleHeader(
                      semester: bundle.semester,
                      schedules: scheduleBundles,
                      selectedWeek: headerWeek,
                      onSelectWeek: (value) => _selectWeek(bundle, value),
                      onToday: () =>
                          _selectWeek(bundle, _defaultWeek(bundle.semester)),
                      onSync: _syncingSchedule
                          ? null
                          : () => _syncCurrentSchedule(bundle),
                      onAddCourse: () => _openCourseEditor(),
                      onSelectSemester: _availableBundles.isEmpty
                          ? null
                          : () => _openSchedulePicker(bundle),
                      onOpenMore: () => _openMoreDock(bundle, headerWeek),
                      onSwitchSchedule: _switchSchedule,
                      onAccounts: () => showAccountCenterDock(context),
                      onImport: _openImporter,
                    );
                  },
                ),
                Expanded(
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: bundle.semester.totalWeeks,
                    onPageChanged: (index) {
                      final pageWeek = index + 1;
                      _setSelectedWeekValue(pageWeek);
                      _prepareWeekLayoutWindow(pageWeek);
                    },
                    itemBuilder: (context, index) {
                      final pageWeek = index + 1;
                      return _ScheduleWeekPage(
                        key: PageStorageKey<String>(
                          '${bundle.semester.id}-$pageWeek',
                        ),
                        semester: bundle.semester,
                        weekIndex: pageWeek,
                        layout: weekLayouts.layoutFor(pageWeek),
                        courseUnits: bundle.schedule.courseUnits,
                        onConflictChoiceChanged:
                            _setConflictChoiceForCurrentBundle,
                        onEditCourse: _openCourseEditor,
                        onDeleteCourse: _deleteCourse,
                        onUpdateCourse: _updateCourse,
                      );
                    },
                    allowImplicitScrolling: true,
                    physics: const PageScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openImporter() async {
    final imported = await Navigator.of(context).push<ScheduleBundle>(
      MaterialPageRoute(builder: (_) => const CupScheduleImportPage()),
    );
    if (!mounted || imported == null) {
      return;
    }
    await _activateSchedule(imported, preferredWeek: null);
  }

  Future<void> _syncCurrentSchedule(ScheduleBundle current) async {
    final sourceSemesterId = current.semester.sourceSemesterId;
    if (sourceSemesterId == null) {
      await _showMessage('这个课表不是从中石大导入的，不能自动同步');
      return;
    }
    setState(() {
      _syncingSchedule = true;
    });

    CupApiClient? client;
    try {
      final lease = await _acquireSessionForSync();
      if (lease == null) {
        return;
      }
      client = lease.client;
      CupSemesterOption? sourceSemester;
      for (final semester in lease.session.semesters) {
        if (semester.id == sourceSemesterId) {
          sourceSemester = semester;
          break;
        }
      }
      if (sourceSemester == null) {
        throw StateError('教务系统没有找到源学期 $sourceSemesterId');
      }
      CupSchedulePayload payload;
      try {
        payload = await client.fetchSchedule(lease.session, sourceSemester);
      } on Object catch (error) {
        if (error is! CupSessionExpiredException) {
          rethrow;
        }
        client.close();
        final renewed = await _renewSessionForSync();
        if (renewed == null) {
          return;
        }
        client = renewed.client;
        payload = await client.fetchSchedule(renewed.session, sourceSemester);
      }
      if (payload.semester.id != sourceSemesterId) {
        throw StateError('同步返回的学期和源学期不一致');
      }

      final localFingerprint = await _store.fingerprintForSemester(
        current.semester.id,
      );
      final sourceFingerprint = await _store.sourceFingerprintForSemester(
        current.semester.id,
      );
      final localChanged =
          localFingerprint != null &&
          sourceFingerprint != null &&
          localFingerprint != sourceFingerprint;
      final incomingFingerprint = schedulePayloadFingerprint(
        semesterJson: payload.semesterJson,
        printDataJson: payload.printDataJson,
      );

      if (!mounted) {
        return;
      }
      if (localChanged) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('覆盖本地修改？'),
            content: Text(
              '当前课表有手工增删改记录。继续同步会用教务数据覆盖这些修改。\n\n'
              '本地指纹：$localFingerprint\n'
              '源数据指纹：$sourceFingerprint\n'
              '新数据指纹：$incomingFingerprint',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('覆盖同步'),
              ),
            ],
          ),
        );
        if (overwrite != true) {
          return;
        }
      }

      final semesterJson = {
        ...payload.semesterJson,
        'id': current.semester.id,
        'nameZh': current.semester.name,
        'name': current.semester.name,
        'sourceSemesterId': sourceSemesterId,
      };
      final saved = await _store.save(
        semesterJson: semesterJson,
        printDataJson: payload.printDataJson,
        selectAfterSave: true,
        updateSourceFingerprint: true,
      );
      if (!mounted) {
        return;
      }
      _applyUpdatedBundle(saved);
      await _showMessage('课表已同步');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      await _showMessage(_cleanSyncError(error));
    } finally {
      client?.close();
      if (mounted) {
        setState(() {
          _syncingSchedule = false;
        });
      }
    }
  }

  Future<void> _showMessage(String message) async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _cleanSyncError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  Future<CupSessionLease?> _acquireSessionForSync() {
    return _sessionForSync(_accountService.acquireSession);
  }

  Future<void> _handleInitialLoadFailure(Object error) async {
    if (!mounted || _handlingLoadError) {
      return;
    }
    _handlingLoadError = true;
    final action = await handleCupAuthFailure(context, error);
    if (!mounted) {
      return;
    }
    _handlingLoadError = false;
    if (action == CupAuthFailureAction.retry) {
      _retryInitialLoad();
      return;
    }
    if (action == CupAuthFailureAction.loggedOut) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              CupLoginPage(onLoginSuccess: (_) => Navigator.of(context).pop()),
        ),
      );
      if (mounted) {
        _retryInitialLoad();
      }
    }
  }

  void _retryInitialLoad() {
    if (!mounted) {
      return;
    }
    setState(() {
      _handledLoadError = null;
      _bundleFuture = _loadBundle();
    });
  }

  Future<CupSessionLease?> _renewSessionForSync() {
    return _sessionForSync(_accountService.refreshSession);
  }

  Future<CupSessionLease?> _sessionForSync(
    Future<CupSessionLease> Function() operation,
  ) async {
    while (mounted) {
      try {
        return await operation();
      } on Object catch (error) {
        if (!mounted) {
          return null;
        }
        final action = await handleCupAuthFailure(context, error);
        if (action != CupAuthFailureAction.retry) {
          return null;
        }
      }
    }
    return null;
  }

  Future<void> _openSchedulePicker(ScheduleBundle current) async {
    final latestBundles = await _loadImportedBundles();
    if (!mounted) {
      return;
    }
    if (latestBundles.isEmpty) {
      setState(() {
        _availableBundles = const [];
      });
      return;
    }
    setState(() {
      _availableBundles = latestBundles;
    });

    final picked = await showModalBottomSheet<ScheduleBundle>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SchedulePickerSheet(
        bundles: latestBundles,
        currentSemesterId: current.semester.id,
        onChangeStartDate: _changeSemesterStartDate,
        onCreateSchedule: _createSchedule,
        onRenameSchedule: _renameSchedule,
        onDeleteSchedule: _deleteSchedule,
      ),
    );
    if (!mounted ||
        picked == null ||
        picked.semester.id == current.semester.id) {
      return;
    }

    await _activateSchedule(
      picked,
      availableBundles: latestBundles,
      preferredWeek: _selectedWeek,
    );
  }

  Future<void> _switchSchedule(ScheduleBundle bundle) async {
    if (_bundle?.semester.id == bundle.semester.id) {
      return;
    }
    _activateScheduleFast(bundle, preferredWeek: _selectedWeek);
  }

  void _activateScheduleFast(ScheduleBundle bundle, {int? preferredWeek}) {
    final week = _clampWeek(
      preferredWeek ?? _defaultWeek(bundle.semester),
      bundle.semester,
    );
    final semesterChanged = _bundle?.semester.id != bundle.semester.id;
    if (semesterChanged) {
      _resetWeekPageController(bundle.semester.id, week);
    }
    setState(() {
      _availableBundles = _mergeScheduleBundles(_availableBundles, bundle);
      _bundle = bundle;
      _conflictChoices = const {};
      _setSelectedWeekValue(week);
    });
    if (!semesterChanged) {
      _syncPageController(week, animate: false);
    }
    unawaited(_persistActivatedSchedule(bundle));
  }

  Future<void> _persistActivatedSchedule(ScheduleBundle bundle) async {
    await _store.setSelectedSemesterId(bundle.semester.id);
    final importedBundles = await _loadImportedBundles();
    final conflictChoices = await _store.loadConflictChoices(
      bundle.semester.id,
    );
    if (!mounted || _bundle?.semester.id != bundle.semester.id) {
      return;
    }
    setState(() {
      _availableBundles = _mergeScheduleBundles(importedBundles, bundle);
      _conflictChoices = conflictChoices;
    });
  }

  Future<void> _activateSchedule(
    ScheduleBundle bundle, {
    List<ScheduleBundle>? availableBundles,
    int? preferredWeek,
  }) async {
    await _store.setSelectedSemesterId(bundle.semester.id);
    final importedBundles = availableBundles ?? await _loadImportedBundles();
    final activeBundle = importedBundles.firstWhere(
      (item) => item.semester.id == bundle.semester.id,
      orElse: () => bundle,
    );
    final conflictChoices = await _store.loadConflictChoices(
      activeBundle.semester.id,
    );
    if (!mounted) {
      return;
    }
    final week = _clampWeek(
      preferredWeek ?? _defaultWeek(activeBundle.semester),
      activeBundle.semester,
    );
    final semesterChanged = _bundle?.semester.id != activeBundle.semester.id;
    if (semesterChanged) {
      _resetWeekPageController(activeBundle.semester.id, week);
    }
    setState(() {
      _availableBundles = _mergeScheduleBundles(importedBundles, activeBundle);
      _bundle = activeBundle;
      _conflictChoices = conflictChoices;
      _setSelectedWeekValue(week);
    });
    if (!semesterChanged) {
      _syncPageController(week, animate: false);
    }
  }

  List<ScheduleBundle> _scheduleBundlesForDisplay(ScheduleBundle current) {
    final merged = _mergeScheduleBundles(_availableBundles, current);
    return [
      current,
      ...merged.where((bundle) => bundle.semester.id != current.semester.id),
    ];
  }

  List<ScheduleBundle> _mergeScheduleBundles(
    List<ScheduleBundle> bundles,
    ScheduleBundle current,
  ) {
    final bySemesterId = <int, ScheduleBundle>{
      for (final bundle in bundles) bundle.semester.id: bundle,
      current.semester.id: current,
    };
    return bySemesterId.values.toList()
      ..sort((a, b) => b.semester.startDate.compareTo(a.semester.startDate));
  }

  Future<void> _openMoreDock(ScheduleBundle current, int selectedWeek) async {
    final schedules = _scheduleBundlesForDisplay(current);
    final pageContext = context;
    final themeController = AppThemeScope.maybeOf(context);
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MoreDockSheet(
        semester: current.semester,
        schedules: [
          current,
          ...schedules.where(
            (bundle) => bundle.semester.id != current.semester.id,
          ),
        ],
        selectedWeek: selectedWeek,
        onSelectWeek: (value) => _selectWeek(current, value, animate: false),
        onToday: () => _selectWeek(
          current,
          _defaultWeek(current.semester),
          animate: false,
        ),
        onSelectSemester: schedules.isEmpty
            ? null
            : () => _openSchedulePicker(current),
        onSwitchSchedule: _switchSchedule,
        onAccounts: () => showAccountCenterDock(pageContext),
        onImport: _openImporter,
        onAbout: () => _openAboutDock(pageContext),
        onTests: () => _openTestDock(pageContext),
        themePreference:
            themeController?.preference ?? BlackbookThemePreference.system,
        onThemePreferenceChanged: (preference) {
          final controller = AppThemeScope.maybeOf(pageContext);
          if (controller != null) {
            unawaited(controller.setPreference(preference));
          }
        },
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    action();
  }

  Future<void> _openAboutDock(BuildContext pageContext) {
    return showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const _AboutDockSheet(),
    );
  }

  Future<void> _openTestDock(BuildContext pageContext) {
    return showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => _TestDockSheet(
        onWidgetMode: () => _openWidgetModeDock(pageContext),
        onDialogPreview: () => _openDialogPreviewDock(pageContext),
      ),
    );
  }

  Future<void> _openWidgetModeDock(BuildContext pageContext) {
    return showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const _WidgetModeDockSheet(),
    );
  }

  Future<void> _openDialogPreviewDock(BuildContext pageContext) {
    return showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const _DialogPreviewDockSheet(),
    );
  }

  Future<void> _changeSemesterStartDate(ScheduleBundle bundle) async {
    final firstDate = DateTime(bundle.semester.endDate.year - 1);
    final lastDate = bundle.semester.endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampDate(bundle.semester.startDate, firstDate, lastDate),
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: '设置开学日期',
      cancelText: '取消',
      confirmText: '保存',
    );
    if (!mounted || picked == null) {
      return;
    }

    await _store.setSemesterStartDate(bundle.semester.id, picked);
    final importedBundles = await _loadImportedBundles();
    final selected = await _store.loadSelected();
    if (!mounted) {
      return;
    }
    final nextBundle =
        selected ??
        importedBundles.firstWhere(
          (item) => item.semester.id == bundle.semester.id,
          orElse: () => bundle,
        );
    final week = _clampWeek(
      _selectedWeek ?? _defaultWeek(nextBundle.semester),
      nextBundle.semester,
    );
    final conflictChoices = await _store.loadConflictChoices(
      nextBundle.semester.id,
    );
    setState(() {
      _availableBundles = importedBundles;
      _bundle = nextBundle;
      _conflictChoices = conflictChoices;
      _setSelectedWeekValue(week);
    });
    _syncPageController(week, animate: false);
  }

  Future<void> _createSchedule() async {
    final current = _bundle;
    if (current == null) {
      return;
    }
    final name = await _askText(
      title: '新建课表',
      label: '课表名称',
      initialValue: '未命名',
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final now = DateTime.now();
    final semester = SemesterInfo(
      id: -now.microsecondsSinceEpoch,
      name: name.trim(),
      startDate: current.semester.startDate,
      endDate: current.semester.endDate,
      weekStartOnSunday: current.semester.weekStartOnSunday,
    );
    final bundle = ScheduleBundle(
      semester: semester,
      schedule: current.schedule.copyWith(activities: const []),
    );
    final saved = await _store.saveBundle(bundle, selectAfterSave: true);
    if (!mounted) {
      return;
    }
    await _activateSchedule(saved, preferredWeek: _selectedWeek);
  }

  Future<void> _renameSchedule(ScheduleBundle bundle) async {
    final name = await _askText(
      title: '重命名课表',
      label: '课表名称',
      initialValue: bundle.semester.name,
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final updated = await _store.renameSemester(
      bundle.semester.id,
      name.trim(),
    );
    if (!mounted) {
      return;
    }
    if (_bundle?.semester.id == updated.semester.id) {
      _applyUpdatedBundle(updated);
    } else {
      final importedBundles = await _loadImportedBundles();
      if (!mounted) {
        return;
      }
      setState(() {
        _availableBundles = importedBundles;
      });
    }
  }

  Future<void> _deleteSchedule(ScheduleBundle bundle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课表？'),
        content: Text('确定删除「${bundle.semester.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _store.deleteSemester(bundle.semester.id);
    final selected = await _store.loadSelected();
    final importedBundles = await _loadImportedBundles();
    if (!mounted) {
      return;
    }
    if (selected == null) {
      setState(() {
        _availableBundles = importedBundles;
        _bundle = null;
        _conflictChoices = const {};
        _setSelectedWeekValue(null);
        _bundleFuture = _loadBundle();
      });
      return;
    }
    await _activateSchedule(selected, availableBundles: importedBundles);
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String initialValue,
  }) async {
    var value = initialValue;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: label),
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.of(context).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(value),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCourseEditor([CourseActivity? activity]) async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final editingWeek = _clampWeek(
      _selectedWeek ?? _defaultWeek(bundle.semester),
      bundle.semester,
    );
    final edited = await Navigator.of(context).push<_CourseEditResult>(
      MaterialPageRoute(
        builder: (_) => _CourseEditorPage(
          semester: bundle.semester,
          activity: activity,
          relatedActivities: activity == null
              ? const []
              : bundle.schedule.activities
                    .where(
                      (item) =>
                          scheduleCourseGroupKey(item) ==
                          scheduleCourseGroupKey(activity),
                    )
                    .toList(),
          selectedWeek: editingWeek,
        ),
      ),
    );
    if (!mounted || edited == null || edited.activities.isEmpty) {
      return;
    }
    final replaceActivityKeys = activity == null
        ? null
        : bundle.schedule.activities
              .where(
                (item) =>
                    scheduleCourseGroupKey(item) ==
                    scheduleCourseGroupKey(activity),
              )
              .map(scheduleActivityStorageKey)
              .toList();
    final updated = _bundleWithUpsertedCourses(
      bundle,
      edited.activities,
      replaceActivityKeys: replaceActivityKeys,
    );
    _applyUpdatedBundle(updated, preferredWeek: editingWeek);
    _schedulePersistBundle(updated);
  }

  Future<void> _updateCourse(CourseActivity activity) async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final updateWeek = _clampWeek(
      _selectedWeek ?? _defaultWeek(bundle.semester),
      bundle.semester,
    );
    final relatedActivities = bundle.schedule.activities
        .where(
          (item) =>
              scheduleCourseGroupKey(item) == scheduleCourseGroupKey(activity),
        )
        .toList();
    final updatedActivities = relatedActivities.isEmpty
        ? [activity]
        : [
            for (final item in relatedActivities)
              item.copyWith(
                iconKey: activity.iconKey,
                clearIconKey: activity.iconKey == null,
                colorKey: activity.colorKey,
                clearColorKey: activity.colorKey == null,
                courseNature: activity.courseNature,
                programType: activity.programType,
              ),
          ];
    final updated = _bundleWithUpsertedCourses(
      bundle,
      updatedActivities,
      replaceActivityKeys: relatedActivities.isEmpty
          ? [scheduleActivityStorageKey(activity)]
          : relatedActivities.map(scheduleActivityStorageKey).toList(),
    );
    _applyUpdatedBundle(updated, preferredWeek: updateWeek);
    _schedulePersistBundle(updated);
  }

  Future<void> _deleteCourse(CourseActivity activity) async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final deleteWeek = _clampWeek(
      _selectedWeek ?? _defaultWeek(bundle.semester),
      bundle.semester,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课程？'),
        content: Text('确定删除「${activity.courseName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final activityKeys = bundle.schedule.activities
        .where(
          (item) =>
              scheduleCourseGroupKey(item) == scheduleCourseGroupKey(activity),
        )
        .map(scheduleActivityStorageKey)
        .toList();
    final updated = _bundleWithoutCourses(bundle, activityKeys);
    _applyUpdatedBundle(updated, preferredWeek: deleteWeek);
    _schedulePersistBundle(updated);
  }

  ScheduleBundle _bundleWithUpsertedCourses(
    ScheduleBundle bundle,
    List<CourseActivity> activities, {
    List<String>? replaceActivityKeys,
  }) {
    final replacementKeys = {
      ...?replaceActivityKeys,
      for (final activity in activities) scheduleActivityStorageKey(activity),
    };
    final nextActivities = [
      for (final activity in bundle.schedule.activities)
        if (!replacementKeys.contains(scheduleActivityStorageKey(activity)))
          activity,
      ...activities,
    ]..sort(CourseActivity.compareByTime);
    return bundle.copyWith(
      schedule: bundle.schedule.copyWith(activities: nextActivities),
    );
  }

  ScheduleBundle _bundleWithoutCourses(
    ScheduleBundle bundle,
    List<String> activityKeys,
  ) {
    final keys = activityKeys.toSet();
    final nextActivities = [
      for (final activity in bundle.schedule.activities)
        if (!keys.contains(scheduleActivityStorageKey(activity))) activity,
    ];
    return bundle.copyWith(
      schedule: bundle.schedule.copyWith(activities: nextActivities),
    );
  }

  void _schedulePersistBundle(ScheduleBundle bundle) {
    _pendingPersistBundle = bundle;
    final generation = ++_bundlePersistGeneration;
    _bundlePersistTimer?.cancel();
    _bundlePersistTimer = Timer(const Duration(milliseconds: 260), () {
      final pending = _pendingPersistBundle;
      if (pending == null || generation != _bundlePersistGeneration) {
        return;
      }
      _pendingPersistBundle = null;
      unawaited(_persistBundleInBackground(pending, generation));
    });
  }

  Future<void> _persistBundleInBackground(
    ScheduleBundle bundle,
    int generation,
  ) async {
    try {
      await _store.saveBundle(bundle, selectAfterSave: true);
    } on Object catch (error) {
      if (!mounted || generation != _bundlePersistGeneration) {
        return;
      }
      _pendingPersistBundle = bundle;
      await _showMessage('课表保存失败：${_cleanScheduleError(error)}');
    }
  }

  String _cleanScheduleError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  void _applyUpdatedBundle(ScheduleBundle updated, {int? preferredWeek}) {
    final week = _clampWeek(
      preferredWeek ?? _selectedWeek ?? _defaultWeek(updated.semester),
      updated.semester,
    );
    setState(() {
      _bundle = updated;
      _availableBundles = _mergeScheduleBundles(_availableBundles, updated);
      _setSelectedWeekValue(week);
      _weekLayoutCache = null;
      _weekLayoutGeneration++;
      _weekLayoutWarmupPending = false;
      _weekLayoutWarmupTimer?.cancel();
      _weekLayoutWarmupTimer = null;
    });
    _syncPageController(week, animate: false);
  }

  DateTime _clampDate(DateTime value, DateTime firstDate, DateTime lastDate) {
    if (value.isBefore(firstDate)) {
      return firstDate;
    }
    if (value.isAfter(lastDate)) {
      return lastDate;
    }
    return value;
  }

  PageController _pageControllerFor(int semesterId, int selectedWeek) {
    if (_weekPageController == null ||
        _weekPageControllerSemesterId != semesterId) {
      _resetWeekPageController(semesterId, selectedWeek);
    }
    return _weekPageController!;
  }

  void _resetWeekPageController(int semesterId, int selectedWeek) {
    final oldController = _weekPageController;
    _weekPageControllerSemesterId = semesterId;
    _weekPageController = PageController(
      initialPage: math.max(0, selectedWeek - 1),
    );
    if (oldController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    }
  }

  _WeekLayoutCache _layoutCacheFor(ScheduleBundle bundle) {
    final activitiesIdentity = identityHashCode(bundle.schedule.activities);
    final choiceFingerprint = _conflictChoicesFingerprint();
    final shouldRebuild =
        _weekLayoutCache == null ||
        _weekLayoutSemesterId != bundle.semester.id ||
        _weekLayoutActivitiesIdentity != activitiesIdentity ||
        _weekLayoutChoiceFingerprint != choiceFingerprint;
    if (shouldRebuild) {
      _weekLayoutCache = _WeekLayoutCache(
        totalWeeks: bundle.semester.totalWeeks,
        activities: bundle.schedule.activities,
        conflictChoices: _conflictChoices,
      );
      _weekLayoutSemesterId = bundle.semester.id;
      _weekLayoutActivitiesIdentity = activitiesIdentity;
      _weekLayoutChoiceFingerprint = choiceFingerprint;
      _weekLayoutGeneration++;
      _weekLayoutWarmupPending = false;
      _weekLayoutWarmupTimer?.cancel();
      _weekLayoutWarmupTimer = null;
    }
    return _weekLayoutCache!;
  }

  void _prepareWeekLayouts(_WeekLayoutCache cache, int centerWeek) {
    final normalizedCenter = _clampWeekByTotal(centerWeek, cache.totalWeeks);
    _weekLayoutWarmupCenterWeek = normalizedCenter;
    cache.ensurePrepared(normalizedCenter);
    if (normalizedCenter > 1) {
      cache.ensurePrepared(normalizedCenter - 1);
    }
    if (normalizedCenter < cache.totalWeeks) {
      cache.ensurePrepared(normalizedCenter + 1);
    }
    if (_weekLayoutWarmupPending || cache.isComplete) {
      return;
    }
    _weekLayoutWarmupPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleWeekLayoutWarmup(_weekLayoutGeneration);
    });
  }

  void _prepareWeekLayoutWindow(int centerWeek) {
    final cache = _weekLayoutCache;
    if (cache == null) {
      return;
    }
    _prepareWeekLayouts(cache, centerWeek);
  }

  void _scheduleWeekLayoutWarmup(int generation) {
    _weekLayoutWarmupTimer?.cancel();
    _weekLayoutWarmupTimer = Timer(const Duration(milliseconds: 90), () {
      _warmRemainingWeekLayouts(generation);
    });
  }

  void _warmRemainingWeekLayouts(int generation) {
    if (!mounted || generation != _weekLayoutGeneration) {
      _weekLayoutWarmupPending = false;
      _weekLayoutWarmupTimer = null;
      return;
    }
    final cache = _weekLayoutCache;
    if (cache == null || cache.isComplete) {
      _weekLayoutWarmupPending = false;
      _weekLayoutWarmupTimer = null;
      return;
    }

    var prepared = 0;
    final budget = Stopwatch()..start();
    while (prepared < 2 && budget.elapsedMicroseconds < 4500) {
      final nextWeek = cache.nextMissingWeekNear(_weekLayoutWarmupCenterWeek);
      if (nextWeek == null) {
        _weekLayoutWarmupPending = false;
        _weekLayoutWarmupTimer = null;
        return;
      }
      cache.ensurePrepared(nextWeek);
      prepared++;
    }
    if (cache.isComplete) {
      _weekLayoutWarmupPending = false;
      _weekLayoutWarmupTimer = null;
      return;
    }
    _scheduleWeekLayoutWarmup(generation);
  }

  int _conflictChoicesFingerprint() {
    if (_conflictChoices.isEmpty) {
      return 0;
    }
    final entries = _conflictChoices.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }

  void _selectWeek(
    ScheduleBundle bundle,
    int requestedWeek, {
    bool animate = true,
  }) {
    final nextWeek = _clampWeek(requestedWeek, bundle.semester);
    _setSelectedWeekValue(nextWeek);
    _prepareWeekLayoutWindow(nextWeek);
    _syncPageController(nextWeek, animate: animate);
  }

  void _setSelectedWeekValue(int? week) {
    _selectedWeek = week;
    if (week != null && _selectedWeekNotifier.value != week) {
      _selectedWeekNotifier.value = week;
    }
  }

  void _syncPageController(int week, {bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _weekPageController;
      if (!mounted || controller == null || !controller.hasClients) {
        return;
      }
      final targetPage = math.max(0, week - 1);
      final currentPage = controller.page?.round() ?? controller.initialPage;
      if (currentPage == targetPage) {
        return;
      }
      if (animate) {
        controller.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        controller.jumpToPage(targetPage);
      }
    });
  }

  int _clampWeek(int week, SemesterInfo semester) {
    return _clampWeekByTotal(week, semester.totalWeeks);
  }

  int _clampWeekByTotal(int week, int totalWeeks) {
    return week.clamp(1, totalWeeks);
  }

  int _defaultWeek(SemesterInfo semester) {
    final today = DateTime.now();
    if (today.isBefore(semester.startDate)) {
      return 1;
    }
    if (today.isAfter(semester.endDate)) {
      return semester.totalWeeks;
    }
    return semester.weekIndexFor(today);
  }

  Future<void> _setConflictChoiceForCurrentBundle(
    _ConflictChoiceUpdate update,
  ) async {
    final bundle = _bundle;
    if (bundle == null) {
      return;
    }
    final storageKey = ImportedScheduleStore.conflictChoiceKey(
      weekIndex: update.weekIndex,
      groupKey: update.groupKey,
    );
    setState(() {
      _conflictChoices = {
        ..._conflictChoices,
        storageKey: update.selectedActivityKey,
      };
      _weekLayoutCache = null;
      _weekLayoutGeneration++;
      _weekLayoutWarmupPending = false;
      _weekLayoutWarmupTimer?.cancel();
      _weekLayoutWarmupTimer = null;
    });
    unawaited(
      _store.setConflictChoice(
        semesterId: bundle.semester.id,
        weekIndex: update.weekIndex,
        groupKey: update.groupKey,
        selectedActivityKey: update.selectedActivityKey,
      ),
    );
  }
}

class _ScheduleWeekPage extends StatefulWidget {
  const _ScheduleWeekPage({
    super.key,
    required this.semester,
    required this.weekIndex,
    required this.layout,
    required this.courseUnits,
    required this.onConflictChoiceChanged,
    required this.onEditCourse,
    required this.onDeleteCourse,
    required this.onUpdateCourse,
  });

  final SemesterInfo semester;
  final int weekIndex;
  final _WeekLayout layout;
  final List<CourseUnit> courseUnits;
  final ValueChanged<_ConflictChoiceUpdate> onConflictChoiceChanged;
  final ValueChanged<CourseActivity> onEditCourse;
  final ValueChanged<CourseActivity> onDeleteCourse;
  final ValueChanged<CourseActivity> onUpdateCourse;

  @override
  State<_ScheduleWeekPage> createState() => _ScheduleWeekPageState();
}

class _ScheduleWeekPageState extends State<_ScheduleWeekPage>
    with AutomaticKeepAliveClientMixin<_ScheduleWeekPage> {
  late Map<int, CourseUnit> _courseUnitByIndex;

  @override
  void initState() {
    super.initState();
    _courseUnitByIndex = _buildCourseUnitMap(widget.courseUnits);
  }

  @override
  void didUpdateWidget(covariant _ScheduleWeekPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.courseUnits, widget.courseUnits)) {
      _courseUnitByIndex = _buildCourseUnitMap(widget.courseUnits);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _WeekTitleRow(
          semester: widget.semester,
          selectedWeek: widget.weekIndex,
        ),
        Expanded(
          child: _ScheduleTimetable(
            weekIndex: widget.weekIndex,
            layout: widget.layout,
            courseUnitByIndex: _courseUnitByIndex,
            onConflictChoiceChanged: widget.onConflictChoiceChanged,
            onEditCourse: widget.onEditCourse,
            onDeleteCourse: widget.onDeleteCourse,
            onUpdateCourse: widget.onUpdateCourse,
          ),
        ),
      ],
    );
  }

  Map<int, CourseUnit> _buildCourseUnitMap(List<CourseUnit> units) {
    return {for (final unit in units) unit.indexNo: unit};
  }

  @override
  bool get wantKeepAlive => true;
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.semester,
    required this.schedules,
    required this.selectedWeek,
    required this.onSelectWeek,
    required this.onToday,
    required this.onSync,
    required this.onAddCourse,
    required this.onSelectSemester,
    required this.onOpenMore,
    required this.onSwitchSchedule,
    required this.onAccounts,
    required this.onImport,
  });

  final SemesterInfo semester;
  final List<ScheduleBundle> schedules;
  final int selectedWeek;
  final ValueChanged<int> onSelectWeek;
  final VoidCallback onToday;
  final VoidCallback? onSync;
  final VoidCallback onAddCourse;
  final VoidCallback? onSelectSemester;
  final VoidCallback onOpenMore;
  final ValueChanged<ScheduleBundle> onSwitchSchedule;
  final VoidCallback onAccounts;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final today = semester.dateFor(weekIndex: selectedWeek, weekday: 7);
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onToday,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${today.month}/${today.day}/${today.year % 100}',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: palette.ink,
                      fontSize: 31,
                      fontWeight: FontWeight.w800,
                      height: 0.98,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        flex: 0,
                        child: Text(
                          '第$selectedWeek周',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.subtle,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onSelectSemester,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _semesterDisplayName(semester.name),
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: palette.subtle,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0,
                                        ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 15,
                                    color: palette.subtle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _HeaderIconButton(
            icon: Icons.sync,
            tooltip: '同步当前课表',
            onPressed: onSync,
          ),
          _HeaderIconButton(
            icon: Icons.add,
            tooltip: '新增课程',
            onPressed: onAddCourse,
          ),
          _HeaderIconButton(
            icon: Icons.file_download_outlined,
            tooltip: '登录并导入课表',
            onPressed: onImport,
          ),
          _HeaderIconButton(
            icon: Icons.more_vert,
            tooltip: '更多',
            iconSize: 31,
            onPressed: onOpenMore,
          ),
        ],
      ),
    );
  }
}

class _CourseIconPickerSheet extends StatelessWidget {
  const _CourseIconPickerSheet({
    required this.currentIconKey,
    required this.fallbackActivity,
  });

  final String? currentIconKey;
  final CourseActivity fallbackActivity;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final autoAccent = _automaticCourseAccentFor(fallbackActivity);
    final palette = blackbookPalette(context);
    return FractionallySizedBox(
      heightFactor: 0.44,
      alignment: Alignment.bottomCenter,
      widthFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.handle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '课程图标',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView(
                    physics: const ClampingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 78,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.70,
                        ),
                    children: [
                      _CourseIconChoiceTile(
                        label: '自动',
                        accent: autoAccent,
                        selected: currentIconKey == null,
                        onTap: () => Navigator.of(context).pop(''),
                      ),
                      for (final accent in _courseAccentOptions)
                        _CourseIconChoiceTile(
                          label: accent.label,
                          accent: accent,
                          selected: currentIconKey == accent.key,
                          onTap: () => Navigator.of(context).pop(accent.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseIconChoiceTile extends StatelessWidget {
  const _CourseIconChoiceTile({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final _CourseAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final accentForeground = _accentForegroundFor(context, accent);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(accent.icon, color: accentForeground, size: 24),
                if (selected)
                  Positioned(
                    right: -9,
                    top: -8,
                    child: Icon(
                      Icons.check_circle,
                      size: 13,
                      color: palette.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? accentForeground : palette.subtle,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: selected ? 22 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 25,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: iconSize,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        color: palette.ink,
        disabledColor: palette.muted.withValues(alpha: 0.42),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MoreDockSheet extends StatefulWidget {
  const _MoreDockSheet({
    required this.semester,
    required this.schedules,
    required this.selectedWeek,
    required this.onSelectWeek,
    required this.onToday,
    required this.onSelectSemester,
    required this.onSwitchSchedule,
    required this.onAccounts,
    required this.onImport,
    required this.onAbout,
    required this.onTests,
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final SemesterInfo semester;
  final List<ScheduleBundle> schedules;
  final int selectedWeek;
  final ValueChanged<int> onSelectWeek;
  final VoidCallback onToday;
  final VoidCallback? onSelectSemester;
  final ValueChanged<ScheduleBundle> onSwitchSchedule;
  final VoidCallback onAccounts;
  final VoidCallback onImport;
  final VoidCallback onAbout;
  final VoidCallback onTests;
  final BlackbookThemePreference themePreference;
  final ValueChanged<BlackbookThemePreference> onThemePreferenceChanged;

  @override
  State<_MoreDockSheet> createState() => _MoreDockSheetState();
}

class _MoreDockSheetState extends State<_MoreDockSheet> {
  late double _weekValue;
  late BlackbookThemePreference _themePreference;

  @override
  void initState() {
    super.initState();
    _weekValue = widget.selectedWeek.toDouble();
    _themePreference = widget.themePreference;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final palette = blackbookPalette(context);
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + bottomPadding),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DockPanel(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('周次', style: _dockLabelStyle(context)),
                            const Spacer(),
                            _DockTextButton(
                              label: '回到当前周',
                              onTap: () => _closeWithAction(widget.onToday),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 10,
                            activeTrackColor: palette.primarySoft,
                            inactiveTrackColor: palette.primary.withValues(
                              alpha: 0.34,
                            ),
                            thumbColor: palette.dockText,
                            overlayColor: palette.primarySoft.withValues(
                              alpha: 0.18,
                            ),
                          ),
                          child: Slider(
                            min: 1,
                            max: widget.semester.totalWeeks.toDouble(),
                            divisions: math.max(
                              1,
                              widget.semester.totalWeeks - 1,
                            ),
                            value: _weekValue.clamp(
                              1.0,
                              widget.semester.totalWeeks.toDouble(),
                            ),
                            onChanged: (value) {
                              setState(() => _weekValue = value);
                            },
                            onChangeEnd: (value) {
                              widget.onSelectWeek(value.round());
                            },
                          ),
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Text('课表', style: _dockLabelStyle(context)),
                            const Spacer(),
                            _DockTextButton(
                              label: '导入',
                              onTap: () => _closeWithAction(widget.onImport),
                            ),
                            const SizedBox(width: 18),
                            _DockTextButton(
                              label: '管理',
                              enabled: widget.onSelectSemester != null,
                              onTap: () => _closeWithAction(
                                widget.onSelectSemester ?? () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        _DockScheduleList(
                          schedules: widget.schedules,
                          currentSemesterId: widget.semester.id,
                          onSwitch: (bundle) => _closeWithAction(
                            () => widget.onSwitchSchedule(bundle),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _DockPanel(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                    child: GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 92,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1.08,
                          ),
                      children: [
                        _DockAction(
                          icon: Icons.today_outlined,
                          label: '回到本周',
                          onTap: () => _closeWithAction(widget.onToday),
                        ),
                        _DockAction(
                          icon: Icons.chevron_left,
                          label: '上一周',
                          onTap: () {
                            _closeWithAction(() {
                              final week = math.max(1, widget.selectedWeek - 1);
                              widget.onSelectWeek(week);
                            });
                          },
                        ),
                        _DockAction(
                          icon: Icons.chevron_right,
                          label: '下一周',
                          onTap: () {
                            _closeWithAction(() {
                              final week = math.min(
                                widget.semester.totalWeeks,
                                widget.selectedWeek + 1,
                              );
                              widget.onSelectWeek(week);
                            });
                          },
                        ),
                        _DockAction(
                          icon: Icons.file_download_outlined,
                          label: '导入中石大',
                          onTap: () => _closeWithAction(widget.onImport),
                        ),
                        _DockAction(
                          icon: Icons.info_outline,
                          label: '关于',
                          onTap: () => _closeWithAction(widget.onAbout),
                          onLongPress: () => _closeWithAction(widget.onTests),
                        ),
                        _DockAction(
                          icon: Icons.manage_accounts_outlined,
                          label: '账号管理',
                          onTap: () => _closeWithAction(widget.onAccounts),
                        ),
                        _DockAction(
                          icon: Icons.calendar_month_outlined,
                          label: '开学日期',
                          enabled: widget.onSelectSemester != null,
                          onTap: () => _closeWithAction(
                            widget.onSelectSemester ?? () {},
                          ),
                        ),
                        _DockAction(
                          icon: _themePreference.icon,
                          label: '主题 ${_themePreference.label}',
                          onTap: _cycleTheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _closeWithAction(VoidCallback action) {
    Navigator.of(context).pop(action);
  }

  void _cycleTheme() {
    final next = _themePreference.next;
    setState(() {
      _themePreference = next;
    });
    widget.onThemePreferenceChanged(next);
  }

  TextStyle? _dockLabelStyle(BuildContext context) {
    final palette = blackbookPalette(context);
    return Theme.of(context).textTheme.titleMedium?.copyWith(
      color: palette.dockText.withValues(alpha: 0.88),
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );
  }
}

class _DockPanel extends StatelessWidget {
  const _DockPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final border = Theme.of(context).brightness == Brightness.dark
        ? null
        : Border.all(color: palette.dockBorder, width: 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.dockBackground,
        borderRadius: BorderRadius.circular(18),
        border: border,
      ),
      child: child,
    );
  }
}

class _DockTextButton extends StatelessWidget {
  const _DockTextButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: enabled ? palette.dockText : palette.dockMuted,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DockScheduleList extends StatelessWidget {
  const _DockScheduleList({
    required this.schedules,
    required this.currentSemesterId,
    required this.onSwitch,
  });

  final List<ScheduleBundle> schedules;
  final int currentSemesterId;
  final ValueChanged<ScheduleBundle> onSwitch;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var index = 0; index < schedules.length; index++) ...[
            _DockScheduleTile(
              bundle: schedules[index],
              selected: schedules[index].semester.id == currentSemesterId,
              onTap: schedules[index].semester.id == currentSemesterId
                  ? null
                  : () => onSwitch(schedules[index]),
            ),
            if (index != schedules.length - 1) const SizedBox(width: 22),
          ],
        ],
      ),
    );
  }
}

class _DockScheduleTile extends StatelessWidget {
  const _DockScheduleTile({
    required this.bundle,
    required this.selected,
    required this.onTap,
  });

  final ScheduleBundle bundle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semester = bundle.semester;
    final palette = blackbookPalette(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? palette.primarySoft : palette.surfaceAlt,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: palette.courseShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: SizedBox(
                width: 62,
                height: 62,
                child: selected
                    ? Icon(Icons.check, size: 38, color: palette.primary)
                    : null,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _shortScheduleName(semester.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.dockText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortScheduleName(String name) {
    final trimmed = name.trim();
    final match = RegExp(r'(\d{4})-(\d{4})-(\d+)').firstMatch(trimmed);
    if (match == null) {
      return trimmed.isEmpty ? '未命名' : trimmed;
    }
    final start = match.group(1)!.substring(2);
    final end = match.group(2)!.substring(2);
    final term = match.group(3)!;
    return '$start-$end-$term';
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final foreground = enabled ? palette.dockText : palette.dockMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: foreground),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.08,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutDockSheet extends StatelessWidget {
  const _AboutDockSheet();

  static final Uri _githubProfileUrl = Uri.parse(
    'https://github.com/danvei233',
  );

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomPadding),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _AboutLogo(palette: palette),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '中石大课表',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.ink,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        iconSize: 22,
                        color: palette.subtle,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '面向中国石油大学（北京）同学的课表工具，方便查看课程、同步教务课表和管理本地课程信息。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.subtle,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AboutInfoLine(
                    label: '作者',
                    value: 'danvei233@github',
                    onTap: () => _openGithubProfile(context),
                  ),
                  const SizedBox(height: 8),
                  _AboutInfoLine(label: '开发者', value: '24届学生丁薇（化名）'),
                  const SizedBox(height: 8),
                  _AboutInfoLine(
                    label: '协助',
                    value: '使用 Codex + ChatGPT 5.5 协助开发',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '部分界面与交互参考 WakeUp 课程表开源版本，并按其 Apache-2.0 许可保留致谢。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openGithubProfile(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await launchUrl(
      _githubProfileUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger?.showSnackBar(const SnackBar(content: Text('无法打开 GitHub 主页')));
    }
  }
}

class _AboutLogo extends StatelessWidget {
  const _AboutLogo({required this.palette});

  final BlackbookPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Image.asset(
          'assets/account/cup_logo.png',
          width: 46,
          height: 46,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _AboutInfoLine extends StatelessWidget {
  const _AboutInfoLine({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.subtle,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: onTap == null ? palette.ink : palette.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
                decoration: onTap == null ? null : TextDecoration.underline,
                decorationColor: palette.primary,
                decorationThickness: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TestDockSheet extends StatefulWidget {
  const _TestDockSheet({
    required this.onWidgetMode,
    required this.onDialogPreview,
  });

  final VoidCallback onWidgetMode;
  final VoidCallback onDialogPreview;

  @override
  State<_TestDockSheet> createState() => _TestDockSheetState();
}

class _TestDockSheetState extends State<_TestDockSheet> {
  var _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return _SimpleDockFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockHeader(title: '测试面板', icon: Icons.science_outlined),
          const SizedBox(height: 12),
          _DockListAction(
            icon: Icons.notifications_active_outlined,
            title: '测试灵动岛/上课提醒',
            subtitle: 'Android 使用高优先级通知模拟横幅提醒',
            busy: _busy,
            onTap: _testNotification,
          ),
          const SizedBox(height: 8),
          _DockListAction(
            icon: Icons.widgets_outlined,
            title: '小组件显示内容',
            subtitle: '设置实时今日或指定日期时间',
            onTap: () {
              Navigator.of(context).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  widget.onWidgetMode();
                }
              });
            },
          ),
          const SizedBox(height: 8),
          _DockListAction(
            icon: Icons.web_asset_outlined,
            title: '弹窗预览',
            subtitle: '查看登录、覆盖、删除与错误提示',
            onTap: () {
              Navigator.of(context).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  widget.onDialogPreview();
                }
              });
            },
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.subtle,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _testNotification() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await ScheduleWidgetBridge.showClassReminderTest();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _message = ok ? '已触发测试通知' : '已请求通知权限，请在系统通知设置中开启';
    });
  }
}

class _DialogPreviewDockSheet extends StatelessWidget {
  const _DialogPreviewDockSheet();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return _SimpleDockFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DockHeader(title: '弹窗预览', icon: Icons.web_asset_outlined),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _DockListAction(
                    icon: Icons.lock_outline,
                    title: '登录信息错误',
                    subtitle: '账号密码错误时的重试与登出弹窗',
                    onTap: () => showCupCredentialsErrorDialog(context),
                  ),
                  _DockListAction(
                    icon: Icons.sync_problem_outlined,
                    title: '覆盖本地修改',
                    subtitle: '同步教务课表前的覆盖确认',
                    onTap: () => _showConfirmDialog(
                      context,
                      title: '覆盖本地修改？',
                      content:
                          '当前课表有手工增删改记录。继续同步会用教务数据覆盖这些修改。\n\n'
                          '本地指纹：2f5e8c10\n源数据指纹：9a74d6b2\n新数据指纹：c3184a90',
                      confirmLabel: '覆盖同步',
                    ),
                  ),
                  _DockListAction(
                    icon: Icons.file_download_outlined,
                    title: '覆盖已导入课表',
                    subtitle: '重复导入同一学期时的确认弹窗',
                    onTap: () => _showConfirmDialog(
                      context,
                      title: '覆盖已导入课表？',
                      content:
                          '2025-2026-2 已存在，继续会覆盖本地保存的数据。\n\n'
                          '本地指纹：2f5e8c10\n新数据指纹：c3184a90\n状态：数据不同',
                      confirmLabel: '覆盖',
                    ),
                  ),
                  _DockListAction(
                    icon: Icons.delete_outline,
                    title: '删除课程',
                    subtitle: '删除整门课程及其时间段的确认弹窗',
                    onTap: () => _showConfirmDialog(
                      context,
                      title: '删除课程？',
                      content: '确定删除「计算机网络原理」吗？',
                      confirmLabel: '删除',
                    ),
                  ),
                  _DockListAction(
                    icon: Icons.drive_file_rename_outline,
                    title: '重命名课表',
                    subtitle: '课表名称编辑弹窗',
                    onTap: () => _showRenameDialog(context),
                  ),
                  _DockListAction(
                    icon: Icons.wifi_off_outlined,
                    title: '网络错误轻提示',
                    subtitle: '非凭据错误只在页面底部提示',
                    onTap: () {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('登录失败，请检查网络'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名课表'),
        content: TextFormField(
          initialValue: '2025-2026-2',
          decoration: const InputDecoration(labelText: '课表名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _WidgetModeDockSheet extends StatefulWidget {
  const _WidgetModeDockSheet();

  @override
  State<_WidgetModeDockSheet> createState() => _WidgetModeDockSheetState();
}

class _WidgetModeDockSheetState extends State<_WidgetModeDockSheet> {
  final _store = const TodayWidgetDisplaySettingsStore();
  late Future<TodayWidgetDisplaySettings> _settingsFuture;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _store.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TodayWidgetDisplaySettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        final settings = snapshot.data ?? TodayWidgetDisplaySettings.live();
        return _SimpleDockFrame(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DockHeader(title: '小组件显示', icon: Icons.widgets_outlined),
              const SizedBox(height: 12),
              _DockListAction(
                icon: settings.mode == TodayWidgetContentMode.live
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                title: '实时今日',
                subtitle: '显示今天当前时间之后的课程',
                onTap: () =>
                    _save(settings.copyWith(mode: TodayWidgetContentMode.live)),
              ),
              const SizedBox(height: 8),
              _DockListAction(
                icon: settings.mode == TodayWidgetContentMode.fixed
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                title: '指定日期时间',
                subtitle:
                    '${settings.fixedDateText}  ${settings.fixedTimeText}',
                onTap: () => _save(
                  settings.copyWith(mode: TodayWidgetContentMode.fixed),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(settings),
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: const Text('日期'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(settings),
                      icon: const Icon(Icons.schedule_outlined, size: 16),
                      label: const Text('时间'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDate(TodayWidgetDisplaySettings settings) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: settings.fixedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '小组件显示日期',
      cancelText: '取消',
      confirmText: '保存',
    );
    if (picked == null) {
      return;
    }
    await _save(
      settings.copyWith(
        mode: TodayWidgetContentMode.fixed,
        fixedDate: DateTime(picked.year, picked.month, picked.day),
      ),
    );
  }

  Future<void> _pickTime(TodayWidgetDisplaySettings settings) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: settings.fixedTime,
      helpText: '小组件显示时间',
      cancelText: '取消',
      confirmText: '保存',
    );
    if (picked == null) {
      return;
    }
    await _save(
      settings.copyWith(mode: TodayWidgetContentMode.fixed, fixedTime: picked),
    );
  }

  Future<void> _save(TodayWidgetDisplaySettings settings) async {
    await _store.save(settings);
    if (!mounted) {
      return;
    }
    setState(() {
      _settingsFuture = Future.value(settings);
    });
  }
}

class _SimpleDockFrame extends StatelessWidget {
  const _SimpleDockFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomPadding),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DockHeader extends StatelessWidget {
  const _DockHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: palette.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          iconSize: 22,
          color: palette.subtle,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _DockListAction extends StatelessWidget {
  const _DockListAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
        child: Row(
          children: [
            busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.primary,
                    ),
                  )
                : Icon(icon, size: 22, color: palette.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _SchedulePickerSheet extends StatelessWidget {
  const _SchedulePickerSheet({
    required this.bundles,
    required this.currentSemesterId,
    required this.onChangeStartDate,
    required this.onCreateSchedule,
    required this.onRenameSchedule,
    required this.onDeleteSchedule,
  });

  final List<ScheduleBundle> bundles;
  final int currentSemesterId;
  final ValueChanged<ScheduleBundle> onChangeStartDate;
  final VoidCallback onCreateSchedule;
  final ValueChanged<ScheduleBundle> onRenameSchedule;
  final ValueChanged<ScheduleBundle> onDeleteSchedule;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final palette = blackbookPalette(context);
    return FractionallySizedBox(
      heightFactor: 0.44,
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '设置当前课表',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _closeThen(context, onCreateSchedule),
                      child: const Text('新建'),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      iconSize: 22,
                      color: palette.subtle,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: bundles.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final bundle = bundles[index];
                      final semester = bundle.semester;
                      final selected = semester.id == currentSemesterId;
                      return InkWell(
                        borderRadius: BorderRadius.circular(7),
                        onTap: () => Navigator.of(context).pop(bundle),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: selected
                                    ? palette.primary
                                    : palette.muted,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      semester.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: palette.ink,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_dateText(semester.startDate)} - '
                                      '${_dateText(semester.endDate)}  '
                                      '${semester.totalWeeks}周',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: palette.subtle,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '设置开学日期',
                                onPressed: () => _closeThen(
                                  context,
                                  () => onChangeStartDate(bundle),
                                ),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                color: palette.subtle,
                                icon: const Icon(Icons.calendar_month_outlined),
                              ),
                              IconButton(
                                tooltip: '重命名',
                                onPressed: () => _closeThen(
                                  context,
                                  () => onRenameSchedule(bundle),
                                ),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                color: palette.subtle,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: '删除课表',
                                onPressed: () => _closeThen(
                                  context,
                                  () => onDeleteSchedule(bundle),
                                ),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                color: palette.danger,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }
}

class _WeekTitleRow extends StatelessWidget {
  const _WeekTitleRow({required this.semester, required this.selectedWeek});

  final SemesterInfo semester;
  final int selectedWeek;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.pageBackground,
        border: Border(
          top: BorderSide(color: palette.divider.withValues(alpha: 0.55)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(38, 5, 6, 5),
      child: SizedBox(
        height: 48,
        child: Row(
          children: List.generate(7, (index) {
            final weekday = index + 1;
            final date = semester.dateFor(
              weekIndex: selectedWeek,
              weekday: weekday,
            );
            final isToday = _isSameDay(date, DateTime.now());
            return Expanded(
              child: _WeekTitleCell(
                date: date,
                weekday: weekday,
                isToday: isToday,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _WeekTitleCell extends StatelessWidget {
  const _WeekTitleCell({
    required this.date,
    required this.weekday,
    required this.isToday,
  });

  final DateTime date;
  final int weekday;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final textColor = isToday ? palette.primary : palette.subtle;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isToday ? 42 : null,
        height: isToday ? 42 : null,
        decoration: BoxDecoration(
          color: isToday ? palette.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isToday
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekdayChinese(weekday),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                height: 1.05,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${date.month}/${date.day}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                height: 1.05,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTimetable extends StatelessWidget {
  const _ScheduleTimetable({
    required this.weekIndex,
    required this.layout,
    required this.courseUnitByIndex,
    required this.onConflictChoiceChanged,
    required this.onEditCourse,
    required this.onDeleteCourse,
    required this.onUpdateCourse,
  });

  final int weekIndex;
  final _WeekLayout layout;
  final Map<int, CourseUnit> courseUnitByIndex;
  final ValueChanged<_ConflictChoiceUpdate> onConflictChoiceChanged;
  final ValueChanged<CourseActivity> onEditCourse;
  final ValueChanged<CourseActivity> onDeleteCourse;
  final ValueChanged<CourseActivity> onUpdateCourse;

  static const double _leftRailWidth = 38;
  static const double _rowHeight = 60;
  static const double _rowGap = 0;
  static const double _dayGap = 4;

  @override
  Widget build(BuildContext context) {
    final maxUnit = _maxUnit();
    final contentHeight = maxUnit * _rowHeight + 14;
    final palette = blackbookPalette(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final dayWidth = (width - _leftRailWidth - 6) / 7;
        return RepaintBoundary(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 14),
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: width,
              height: contentHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var weekday = 0; weekday <= 7; weekday++)
                    Positioned(
                      left: _leftRailWidth + weekday * dayWidth,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 0.6,
                        color: palette.weakDivider.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.08
                              : 0.34,
                        ),
                      ),
                    ),
                  for (var unit = 1; unit <= maxUnit; unit++)
                    Positioned(
                      left: 0,
                      top: (unit - 1) * _rowHeight,
                      width: _leftRailWidth,
                      height: _rowHeight,
                      child: _ScheduleUnitLabel(
                        unit: unit,
                        courseUnit: _unitFor(unit),
                      ),
                    ),
                  for (final item in layout.items)
                    _PositionedCourseBlock(
                      weekIndex: weekIndex,
                      item: item,
                      leftRailWidth: _leftRailWidth,
                      dayWidth: dayWidth,
                      dayGap: _dayGap,
                      rowHeight: _rowHeight,
                      rowGap: _rowGap,
                      onConflictChoiceChanged: onConflictChoiceChanged,
                      onEditCourse: onEditCourse,
                      onDeleteCourse: onDeleteCourse,
                      onUpdateCourse: onUpdateCourse,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _maxUnit() {
    final maxFromUnits = courseUnitByIndex.keys.fold<int>(
      0,
      (current, index) => math.max(current, index),
    );
    final maxFromActivities = layout.maxUnit;
    return math.max(12, math.max(maxFromUnits, maxFromActivities));
  }

  CourseUnit? _unitFor(int index) {
    return courseUnitByIndex[index];
  }
}

class _WeekLayoutCache {
  _WeekLayoutCache({
    required this.totalWeeks,
    required this.activities,
    required this.conflictChoices,
  }) : _activitiesByWeekday = _groupActivitiesByWeekday(activities);

  final int totalWeeks;
  final List<CourseActivity> activities;
  final Map<String, String> conflictChoices;
  final List<List<CourseActivity>> _activitiesByWeekday;
  final Map<int, _WeekLayout> _cache = {};

  _WeekLayout layoutFor(int weekIndex) {
    return ensurePrepared(weekIndex);
  }

  _WeekLayout ensurePrepared(int weekIndex) {
    final normalizedWeek = weekIndex.clamp(1, totalWeeks);
    return _cache.putIfAbsent(
      normalizedWeek,
      () => _buildWeekLayout(normalizedWeek),
    );
  }

  bool get isComplete => _cache.length >= totalWeeks;

  int? nextMissingWeekNear(int centerWeek) {
    final normalizedCenter = centerWeek.clamp(1, totalWeeks);
    for (var distance = 0; distance < totalWeeks; distance++) {
      final right = normalizedCenter + distance;
      if (right <= totalWeeks && !_cache.containsKey(right)) {
        return right;
      }
      final left = normalizedCenter - distance;
      if (left >= 1 && !_cache.containsKey(left)) {
        return left;
      }
    }
    return null;
  }

  static List<List<CourseActivity>> _groupActivitiesByWeekday(
    List<CourseActivity> activities,
  ) {
    final result = List<List<CourseActivity>>.generate(8, (_) => []);
    for (final activity in activities) {
      if (activity.weekday < 1 || activity.weekday > 7) {
        continue;
      }
      result[activity.weekday].add(activity);
    }
    for (final dayActivities in result) {
      dayActivities.sort(_compareByUnitAndName);
    }
    return result;
  }

  _WeekLayout _buildWeekLayout(int weekIndex) {
    final result = <_LaidOutActivity>[];
    for (var weekday = 1; weekday <= 7; weekday++) {
      final currentWeekActivities = _sortedDayActivities(
        weekIndex: weekIndex,
        weekday: weekday,
        onlyCurrentWeek: true,
      );
      result.addAll(
        _layoutDayActivities(
          weekIndex: weekIndex,
          dayActivities: currentWeekActivities,
          outOfWeek: false,
        ),
      );

      final outOfWeekActivities = _outOfWeekFillers(
        weekIndex: weekIndex,
        weekday: weekday,
        currentWeekActivities: currentWeekActivities,
      );
      result.addAll(
        _layoutDayActivities(
          weekIndex: weekIndex,
          dayActivities: outOfWeekActivities,
          outOfWeek: true,
        ),
      );
    }
    final maxUnit = result.fold<int>(
      0,
      (current, item) => math.max(current, item.endUnit),
    );
    return _WeekLayout(items: result, maxUnit: maxUnit);
  }

  List<CourseActivity> _sortedDayActivities({
    required int weekIndex,
    required int weekday,
    required bool onlyCurrentWeek,
  }) {
    if (weekday < 1 || weekday >= _activitiesByWeekday.length) {
      return const [];
    }
    final dayActivities = _activitiesByWeekday[weekday];
    return [
      for (final activity in dayActivities)
        if (onlyCurrentWeek
            ? activity.weekIndexes.contains(weekIndex)
            : _isFutureWeekActivity(activity, weekIndex))
          activity,
    ];
  }

  bool _isFutureWeekActivity(CourseActivity activity, int weekIndex) {
    return !activity.weekIndexes.contains(weekIndex) &&
        activity.weekIndexes.any((item) => item > weekIndex);
  }

  List<CourseActivity> _outOfWeekFillers({
    required int weekIndex,
    required int weekday,
    required List<CourseActivity> currentWeekActivities,
  }) {
    final occupied = <_UnitSpan>[
      for (final activity in currentWeekActivities)
        _UnitSpan(activity.startUnit, activity.endUnit),
    ];
    final candidates = _sortedDayActivities(
      weekIndex: weekIndex,
      weekday: weekday,
      onlyCurrentWeek: false,
    );
    final fillers = <CourseActivity>[];
    for (final activity in candidates) {
      final span = _UnitSpan(activity.startUnit, activity.endUnit);
      final blocked = occupied.any((item) => item.overlaps(span));
      if (blocked) {
        continue;
      }
      fillers.add(activity);
      occupied.add(span);
    }
    return fillers;
  }

  List<_LaidOutActivity> _layoutDayActivities({
    required int weekIndex,
    required List<CourseActivity> dayActivities,
    required bool outOfWeek,
  }) {
    final result = <_LaidOutActivity>[];
    var group = <CourseActivity>[];
    var groupEndUnit = 0;
    for (final activity in dayActivities) {
      if (group.isNotEmpty && activity.startUnit > groupEndUnit) {
        result.add(
          _layoutConflictGroup(
            weekIndex: weekIndex,
            group: group,
            outOfWeek: outOfWeek,
          ),
        );
        group = <CourseActivity>[];
        groupEndUnit = 0;
      }
      group.add(activity);
      groupEndUnit = math.max(groupEndUnit, activity.endUnit);
    }
    if (group.isNotEmpty) {
      result.add(
        _layoutConflictGroup(
          weekIndex: weekIndex,
          group: group,
          outOfWeek: outOfWeek,
        ),
      );
    }
    return result;
  }

  _LaidOutActivity _layoutConflictGroup({
    required int weekIndex,
    required List<CourseActivity> group,
    required bool outOfWeek,
  }) {
    final sorted = [...group]..sort(_compareActivityForDisplay);
    final startUnit = sorted.fold<int>(
      sorted.first.startUnit,
      (value, activity) => math.min(value, activity.startUnit),
    );
    final endUnit = sorted.fold<int>(
      sorted.first.endUnit,
      (value, activity) => math.max(value, activity.endUnit),
    );
    final selected = _selectedActivity(sorted, weekIndex);
    return _LaidOutActivity(
      group: _CourseConflictGroup(
        activities: sorted,
        selectedActivity: selected,
        groupKey: _conflictGroupKey(sorted),
        outOfWeek: outOfWeek,
      ),
      weekday: sorted.first.weekday,
      startUnit: startUnit,
      endUnit: endUnit,
    );
  }

  CourseActivity _selectedActivity(List<CourseActivity> group, int weekIndex) {
    final savedChoice = _savedChoiceFor(group, weekIndex);
    if (savedChoice != null) {
      for (final activity in group) {
        if (_activityChoiceKey(activity) == savedChoice) {
          return activity;
        }
      }
    }
    return group.reduce((best, activity) {
      final scoreCompare = _activityUsefulnessScore(
        activity,
      ).compareTo(_activityUsefulnessScore(best));
      if (scoreCompare != 0) {
        return scoreCompare > 0 ? activity : best;
      }
      return CourseActivity.compareByTime(activity, best) < 0 ? activity : best;
    });
  }

  String? _savedChoiceFor(List<CourseActivity> group, int weekIndex) {
    return conflictChoices[ImportedScheduleStore.conflictChoiceKey(
      weekIndex: weekIndex,
      groupKey: _conflictGroupKey(group),
    )];
  }

  int _activityUsefulnessScore(CourseActivity activity) {
    var score = 0;
    if (activity.room.trim().isNotEmpty &&
        !activity.room.contains('咨询') &&
        !activity.room.contains('具体')) {
      score += 30;
    }
    if (activity.building?.trim().isNotEmpty ?? false) {
      score += 20;
    }
    if (activity.teachers.isNotEmpty) {
      score += 10;
    }
    if (activity.weeksText.trim().isNotEmpty) {
      score += 4;
    }
    score += math.min(activity.weekIndexes.length, 18);
    score -= activity.courseName.contains('非本周') ? 40 : 0;
    return score;
  }

  int _compareActivityForDisplay(CourseActivity a, CourseActivity b) {
    final selectedCompare = _activityUsefulnessScore(
      b,
    ).compareTo(_activityUsefulnessScore(a));
    if (selectedCompare != 0) {
      return selectedCompare;
    }
    return CourseActivity.compareByTime(a, b);
  }

  static int _compareByUnitAndName(CourseActivity a, CourseActivity b) {
    final startCompare = a.startUnit.compareTo(b.startUnit);
    if (startCompare != 0) {
      return startCompare;
    }
    final endCompare = a.endUnit.compareTo(b.endUnit);
    if (endCompare != 0) {
      return endCompare;
    }
    return a.courseName.compareTo(b.courseName);
  }
}

class _ScheduleUnitLabel extends StatelessWidget {
  const _ScheduleUnitLabel({required this.unit, required this.courseUnit});

  final int unit;
  final CourseUnit? courseUnit;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$unit',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: 0,
            ),
          ),
          if (courseUnit != null) ...[
            const SizedBox(height: 2),
            Text(
              courseUnit!.startTimeText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.subtle,
                fontSize: 9,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: 0,
              ),
            ),
            Text(
              courseUnit!.endTimeText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.subtle,
                fontSize: 9,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PositionedCourseBlock extends StatelessWidget {
  const _PositionedCourseBlock({
    required this.weekIndex,
    required this.item,
    required this.leftRailWidth,
    required this.dayWidth,
    required this.dayGap,
    required this.rowHeight,
    required this.rowGap,
    required this.onConflictChoiceChanged,
    required this.onEditCourse,
    required this.onDeleteCourse,
    required this.onUpdateCourse,
  });

  final int weekIndex;
  final _LaidOutActivity item;
  final double leftRailWidth;
  final double dayWidth;
  final double dayGap;
  final double rowHeight;
  final double rowGap;
  final ValueChanged<_ConflictChoiceUpdate> onConflictChoiceChanged;
  final ValueChanged<CourseActivity> onEditCourse;
  final ValueChanged<CourseActivity> onDeleteCourse;
  final ValueChanged<CourseActivity> onUpdateCourse;

  @override
  Widget build(BuildContext context) {
    final group = item.group;
    final left = leftRailWidth + (item.weekday - 1) * dayWidth + dayGap / 2;
    final width = math.max(18.0, dayWidth - dayGap);
    final top = (item.startUnit - 1) * (rowHeight + rowGap);
    final span = math.max(1, item.endUnit - item.startUnit + 1);
    final height = span * rowHeight + (span - 1) * rowGap - 5;

    return Positioned(
      left: left,
      top: top + 2,
      width: width,
      height: math.max(30, height),
      child: _ScheduleCourseBlock(
        weekIndex: weekIndex,
        group: group,
        onConflictChoiceChanged: onConflictChoiceChanged,
        onEditCourse: onEditCourse,
        onDeleteCourse: onDeleteCourse,
        onUpdateCourse: onUpdateCourse,
      ),
    );
  }
}

class _ScheduleCourseBlock extends StatelessWidget {
  const _ScheduleCourseBlock({
    required this.weekIndex,
    required this.group,
    required this.onConflictChoiceChanged,
    required this.onEditCourse,
    required this.onDeleteCourse,
    required this.onUpdateCourse,
  });

  final int weekIndex;
  final _CourseConflictGroup group;
  final ValueChanged<_ConflictChoiceUpdate> onConflictChoiceChanged;
  final ValueChanged<CourseActivity> onEditCourse;
  final ValueChanged<CourseActivity> onDeleteCourse;
  final ValueChanged<CourseActivity> onUpdateCourse;

  @override
  Widget build(BuildContext context) {
    final activity = group.selectedActivity;
    final colorAccent = _courseColorAccentFor(activity);
    final iconAccent = _courseIconAccentFor(activity);
    final palette = blackbookPalette(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseBackground = _accentBackgroundFor(context, colorAccent);
    final background = group.outOfWeek
        ? Color.alphaBlend(
            baseBackground.withValues(alpha: dark ? 0.34 : 0.28),
            palette.pageBackground,
          )
        : baseBackground;
    final textBase = _accentForegroundFor(context, colorAccent);
    final textColor = textBase.withValues(
      alpha: group.outOfWeek ? (dark ? 0.32 : 0.22) : 0.95,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showCourseDetails(context, activity),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.courseBorder, width: 0.55),
          boxShadow: [
            BoxShadow(
              color: palette.courseShadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 4, 5),
                child: _CourseBlockText(
                  activity: activity,
                  iconAccent: iconAccent,
                  outOfWeek: group.outOfWeek,
                  color: textColor,
                ),
              ),
            ),
            if (group.hasConflict && !group.outOfWeek)
              Positioned(
                right: 1,
                bottom: 1,
                child: CustomPaint(
                  size: const Size(12, 12),
                  painter: _ConflictCornerPainter(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCourseDetails(BuildContext context, CourseActivity activity) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) => _CourseDetailSheet(
        activity: activity,
        conflictGroup: group.hasConflict && !group.outOfWeek ? group : null,
        weekIndex: weekIndex,
        onConflictChoiceChanged: (selected) {
          onConflictChoiceChanged(
            _ConflictChoiceUpdate(
              weekIndex: weekIndex,
              groupKey: group.groupKey,
              selectedActivityKey: _activityChoiceKey(selected),
            ),
          );
        },
        onEditCourse: onEditCourse,
        onDeleteCourse: onDeleteCourse,
        onUpdateCourse: onUpdateCourse,
      ),
    );
  }
}

class _ConflictCornerPainter extends CustomPainter {
  const _ConflictCornerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ConflictCornerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CourseBlockText extends StatelessWidget {
  const _CourseBlockText({
    required this.activity,
    required this.iconAccent,
    required this.outOfWeek,
    required this.color,
  });

  final CourseActivity activity;
  final _CourseAccent iconAccent;
  final bool outOfWeek;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          iconAccent.icon,
          size: 13,
          color: color.withValues(alpha: outOfWeek ? 0.26 : 0.84),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Text(
            _blockText,
            textAlign: TextAlign.start,
            maxLines: 9,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontSize: 9.4,
              fontWeight: FontWeight.w600,
              height: 1.32,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }

  String get _blockText {
    final parts = <String>[
      if (outOfWeek) '[非本周]',
      if (activity.programType == CourseProgramType.minor) '[辅修]',
      activity.courseName,
    ];
    final room = activity.room.trim();
    if (room.isNotEmpty) {
      parts.add('@$room');
    }
    final teacher = _shortTeacherName(activity.teacherText);
    if (teacher.isNotEmpty) {
      parts.add(teacher);
    }
    return parts.join('\n');
  }
}

class _CourseBadge extends StatelessWidget {
  const _CourseBadge({
    required this.iconAccent,
    required this.colorAccent,
    required this.size,
  });

  final _CourseAccent iconAccent;
  final _CourseAccent colorAccent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = _accentBackgroundFor(context, colorAccent);
    final foreground = _accentForegroundFor(context, colorAccent);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(iconAccent.icon, color: foreground, size: size * 0.46),
    );
  }
}

class _CourseDetailSheet extends StatelessWidget {
  const _CourseDetailSheet({
    required this.activity,
    required this.conflictGroup,
    required this.weekIndex,
    required this.onConflictChoiceChanged,
    required this.onEditCourse,
    required this.onDeleteCourse,
    required this.onUpdateCourse,
  });

  final CourseActivity activity;
  final _CourseConflictGroup? conflictGroup;
  final int weekIndex;
  final ValueChanged<CourseActivity> onConflictChoiceChanged;
  final ValueChanged<CourseActivity> onEditCourse;
  final ValueChanged<CourseActivity> onDeleteCourse;
  final ValueChanged<CourseActivity> onUpdateCourse;

  @override
  Widget build(BuildContext context) {
    final conflictGroup = this.conflictGroup;
    final iconAccent = _courseIconAccentFor(activity);
    final colorAccent = _courseColorAccentFor(activity);
    final palette = blackbookPalette(context);
    final natureColor = activity.courseNature.contains('选')
        ? const Color(0xFF7A62D8)
        : const Color(0xFF3196D4);
    final programColor = activity.programType == CourseProgramType.minor
        ? const Color(0xFFDA5A76)
        : const Color(0xFF20A077);
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          decoration: BoxDecoration(
            color: palette.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.handle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: '更改图标',
                    child: InkResponse(
                      radius: 32,
                      onTap: () => _changeIcon(context),
                      child: _CourseBadge(
                        iconAccent: iconAccent,
                        colorAccent: colorAccent,
                        size: 50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.courseName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: palette.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              '${activity.credits.toStringAsFixed(1)} 学分',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: palette.subtle,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: natureColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                activity.courseNature,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: natureColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: programColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                activity.programType.label,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: programColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DetailMoreButton(onPressed: () => _showMoreActions(context)),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: palette.divider),
              _DetailLine(
                icon: Icons.person_outline,
                color: const Color(0xFF2586E9),
                label: '授课教师',
                text: activity.teacherText,
              ),
              _DetailLine(
                icon: Icons.location_on_outlined,
                color: const Color(0xFFFF4D4D),
                label: '上课地点',
                text: activity.placeText,
              ),
              _DetailLine(
                icon: Icons.calendar_today_outlined,
                color: const Color(0xFF19B6A6),
                label: '周次',
                text: '第 ${activity.weeksText} 周',
              ),
              _DetailLine(
                icon: Icons.schedule_outlined,
                color: const Color(0xFFFFB12F),
                label: '节次与时间',
                text:
                    '第 ${activity.startUnit} - ${activity.endUnit} 节    '
                    '${activity.startTime} - ${activity.endTime}',
              ),
              _DetailLine(
                icon: Icons.article_outlined,
                color: const Color(0xFFFFD735),
                label: '课程代码',
                text: activity.lessonCode.isEmpty
                    ? activity.courseCode
                    : activity.lessonCode,
              ),
              if (conflictGroup != null) ...[
                const SizedBox(height: 4),
                Text(
                  '本周冲突课程',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.subtle,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                for (final option in conflictGroup.activities)
                  _ConflictCourseOption(
                    option: option,
                    selected:
                        _activityChoiceKey(option) ==
                        _activityChoiceKey(conflictGroup.selectedActivity),
                    onTap: () {
                      onConflictChoiceChanged(option);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyCourseInfo(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: _courseClipboardText(activity)),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('课程信息已复制'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _changeIcon(BuildContext context) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) => _CourseIconPickerSheet(
        currentIconKey: activity.iconKey,
        fallbackActivity: activity,
      ),
    );
    if (!context.mounted || picked == null) {
      return;
    }
    Navigator.of(context).pop();
    if (picked.isEmpty) {
      onUpdateCourse(activity.copyWith(clearIconKey: true));
      return;
    }
    onUpdateCourse(activity.copyWith(iconKey: picked));
  }

  Future<void> _showMoreActions(BuildContext context) async {
    final action = await showModalBottomSheet<_CourseDetailAction>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const _CourseDetailActionsSheet(),
    );
    if (action == null || !context.mounted) {
      return;
    }
    switch (action) {
      case _CourseDetailAction.copy:
        await _copyCourseInfo(context);
      case _CourseDetailAction.edit:
        Navigator.of(context).pop();
        onEditCourse(activity);
      case _CourseDetailAction.delete:
        Navigator.of(context).pop();
        onDeleteCourse(activity);
    }
  }
}

class _ConflictCourseOption extends StatelessWidget {
  const _ConflictCourseOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CourseActivity option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? const Color(0xFF6B5CF6)
                  : const Color(0xFFB6BDCB),
              size: 27,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.courseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected ? palette.ink : palette.subtle,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${option.placeText}  ${_shortTeacherName(option.teacherText)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _CourseEditorPage extends StatefulWidget {
  const _CourseEditorPage({
    required this.semester,
    required this.activity,
    required this.relatedActivities,
    required this.selectedWeek,
  });

  final SemesterInfo semester;
  final CourseActivity? activity;
  final List<CourseActivity> relatedActivities;
  final int selectedWeek;

  @override
  State<_CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<_CourseEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _creditController;
  late final TextEditingController _codeController;
  late final TextEditingController _teacherController;
  late final TextEditingController _roomController;
  late final List<_EditableCourseTimeSlot> _timeSlots;
  String? _iconKey;
  String? _colorKey;
  late String _courseNature;
  late CourseProgramType _programType;

  @override
  void initState() {
    super.initState();
    final activity = widget.activity;
    _nameController = TextEditingController(text: activity?.courseName ?? '');
    _creditController = TextEditingController(
      text: (activity?.credits ?? 0).toStringAsFixed(1),
    );
    _codeController = TextEditingController(
      text: activity?.lessonCode ?? activity?.courseCode ?? '',
    );
    _teacherController = TextEditingController(
      text: activity?.teachers.join(' / ') ?? '',
    );
    _roomController = TextEditingController(text: activity?.room ?? '');
    _iconKey = activity?.iconKey;
    _colorKey = activity?.colorKey;
    _courseNature = activity?.courseNature ?? '必修';
    _programType = activity?.programType ?? CourseProgramType.primary;
    final relatedActivities = widget.relatedActivities.isEmpty
        ? [?activity]
        : widget.relatedActivities;
    _timeSlots = relatedActivities.isEmpty
        ? [_EditableCourseTimeSlot.fromActivity(null, widget)]
        : [
            for (final item in relatedActivities)
              _EditableCourseTimeSlot.fromActivity(item, widget),
          ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _creditController.dispose();
    _codeController.dispose();
    _teacherController.dispose();
    _roomController.dispose();
    for (final slot in _timeSlots) {
      slot.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Scaffold(
      backgroundColor: palette.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 18, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    color: palette.ink,
                    iconSize: 30,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      widget.activity == null ? 'Add Course' : 'Edit Course',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: palette.ink,
                            fontSize: 30,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  TextButton(onPressed: _save, child: const Text('SAVE')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                children: [
                  _EditorField(
                    icon: Icons.bookmark_border,
                    color: const Color(0xFF19B6A6),
                    controller: _nameController,
                    label: '课程名称',
                  ),
                  _EditorField(
                    icon: Icons.flag_outlined,
                    color: const Color(0xFF2586E9),
                    controller: _creditController,
                    label: '学分',
                    keyboardType: TextInputType.number,
                  ),
                  _EditorField(
                    icon: Icons.article_outlined,
                    color: const Color(0xFFFFD735),
                    controller: _codeController,
                    label: '课程代码',
                  ),
                  _CourseIconEditorTile(
                    iconKey: _iconKey,
                    fallbackActivity: _fallbackEditorActivity,
                    onTap: _pickCourseIcon,
                  ),
                  _CourseColorEditorTile(
                    colorKey: _colorKey,
                    fallbackActivity: _fallbackEditorActivity,
                    onTap: _pickCourseColor,
                  ),
                  _CourseNatureEditor(
                    value: _courseNature,
                    onChanged: (value) {
                      setState(() {
                        _courseNature = value;
                      });
                    },
                  ),
                  _CourseProgramEditor(
                    value: _programType,
                    onChanged: (value) {
                      setState(() {
                        _programType = value;
                      });
                    },
                  ),
                  Divider(height: 28, color: palette.divider),
                  for (var index = 0; index < _timeSlots.length; index++)
                    _CourseTimeSlotEditor(
                      slot: _timeSlots[index],
                      index: index,
                      canRemove: _timeSlots.length > 1,
                      onRemove: () => _removeTimeSlot(index),
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey<String>('add-course-time-slot'),
                      onPressed: _addTimeSlot,
                      icon: const Icon(Icons.add),
                      label: const Text('添加时间段'),
                    ),
                  ),
                  _EditorField(
                    icon: Icons.person_outline,
                    color: const Color(0xFF2586E9),
                    controller: _teacherController,
                    label: '教师',
                  ),
                  _EditorField(
                    icon: Icons.meeting_room_outlined,
                    color: const Color(0xFFFF4D4D),
                    controller: _roomController,
                    label: '地点',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final code = _codeController.text.trim();
    final lessonId =
        widget.activity?.lessonId ?? -DateTime.now().microsecondsSinceEpoch;
    final teachers = _teacherController.text
        .split(RegExp(r'[/,，、]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final activities = <CourseActivity>[];
    for (var index = 0; index < _timeSlots.length; index++) {
      final slot = _timeSlots[index];
      final startUnit = int.tryParse(slot.startUnitController.text.trim()) ?? 1;
      final endUnit =
          int.tryParse(slot.endUnitController.text.trim()) ?? startUnit;
      final slotCode = _timeSlots.length == 1 ? code : '$code#$index';
      activities.add(
        CourseActivity(
          lessonId: lessonId,
          lessonCode: slotCode,
          courseCode: code,
          courseName: name,
          weeksText: slot.weeksController.text.trim(),
          weekIndexes: _parseWeeks(slot.weeksController.text, widget.semester),
          weekday: (int.tryParse(slot.weekdayController.text.trim()) ?? 1)
              .clamp(1, 7),
          startUnit: startUnit,
          endUnit: math.max(startUnit, endUnit),
          startTime: slot.startTimeController.text.trim(),
          endTime: slot.endTimeController.text.trim(),
          room: slot.roomController.text.trim(),
          building: null,
          campus: null,
          teachers: teachers,
          credits: double.tryParse(_creditController.text.trim()) ?? 0,
          lessonName: '',
          lessonRemark: null,
          iconKey: _iconKey,
          colorKey: _colorKey,
          courseNature: _courseNature,
          programType: _programType,
        ),
      );
    }
    Navigator.of(context).pop(_CourseEditResult(activities));
  }

  void _addTimeSlot() {
    setState(() {
      _timeSlots.add(_EditableCourseTimeSlot.fromActivity(null, widget));
    });
  }

  void _removeTimeSlot(int index) {
    if (_timeSlots.length <= 1) {
      return;
    }
    final removed = _timeSlots.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _pickCourseIcon() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) => _CourseIconPickerSheet(
        currentIconKey: _iconKey,
        fallbackActivity: _fallbackEditorActivity,
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() {
      _iconKey = picked.isEmpty ? null : picked;
    });
  }

  Future<void> _pickCourseColor() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) => _CourseColorPickerSheet(
        currentColorKey: _colorKey,
        fallbackActivity: _fallbackEditorActivity,
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() {
      _colorKey = picked.isEmpty ? null : picked;
    });
  }

  CourseActivity get _fallbackEditorActivity {
    final base = widget.activity;
    if (base != null) {
      return base.copyWith(
        courseName: _nameController.text.trim().isEmpty
            ? base.courseName
            : _nameController.text.trim(),
        courseCode: _codeController.text.trim().isEmpty
            ? base.courseCode
            : _codeController.text.trim(),
        lessonCode: _codeController.text.trim().isEmpty
            ? base.lessonCode
            : _codeController.text.trim(),
        iconKey: _iconKey,
        clearIconKey: _iconKey == null,
        colorKey: _colorKey,
        clearColorKey: _colorKey == null,
      );
    }
    return CourseActivity(
      lessonId: 0,
      lessonCode: _codeController.text.trim(),
      courseCode: _codeController.text.trim(),
      courseName: _nameController.text.trim(),
      weeksText: '',
      weekIndexes: const [],
      weekday: DateTime.now().weekday,
      startUnit: 1,
      endUnit: 2,
      startTime: '',
      endTime: '',
      room: _roomController.text.trim(),
      building: null,
      campus: null,
      teachers: const [],
      credits: double.tryParse(_creditController.text.trim()) ?? 0,
      lessonName: '',
      lessonRemark: null,
      iconKey: _iconKey,
      colorKey: _colorKey,
      courseNature: _courseNature,
      programType: _programType,
    );
  }

  List<int> _parseWeeks(String text, SemesterInfo semester) {
    final upper = text.toUpperCase();
    final odd = upper.contains('ODD') || text.contains('单');
    final even = upper.contains('EVEN') || text.contains('双');
    final weeks = <int>{};
    final matches = RegExp(r'\d+\s*(?:-\s*\d+)?').allMatches(text);
    for (final match in matches) {
      final part = match.group(0)!.replaceAll(' ', '');
      final rangeParts = part.split('-');
      final start = int.tryParse(rangeParts.first);
      final end = rangeParts.length > 1 ? int.tryParse(rangeParts.last) : start;
      if (start == null || end == null) {
        continue;
      }
      for (var week = start; week <= end; week++) {
        if (week < 1 || week > semester.totalWeeks) {
          continue;
        }
        if (odd && week.isEven) {
          continue;
        }
        if (even && week.isOdd) {
          continue;
        }
        weeks.add(week);
      }
    }
    if (weeks.isEmpty) {
      weeks.add(widget.selectedWeek);
    }
    return weeks.toList()..sort();
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.icon,
    required this.color,
    required this.controller,
    required this.label,
    this.keyboardType,
  });

  final IconData icon;
  final Color color;
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(width: 18),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: TextStyle(
                color: palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: palette.muted),
                enabledBorder: InputBorder.none,
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: palette.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseIconEditorTile extends StatelessWidget {
  const _CourseIconEditorTile({
    required this.iconKey,
    required this.fallbackActivity,
    required this.onTap,
  });

  final String? iconKey;
  final CourseActivity fallbackActivity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _courseIconAccentFor(fallbackActivity);
    final palette = blackbookPalette(context);
    final iconColor = _accentForegroundFor(context, accent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(accent.icon, color: iconColor, size: 25),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  iconKey == null ? '课程图标：自动匹配' : '课程图标：${accent.label}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: palette.muted, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseColorEditorTile extends StatelessWidget {
  const _CourseColorEditorTile({
    required this.colorKey,
    required this.fallbackActivity,
    required this.onTap,
  });

  final String? colorKey;
  final CourseActivity fallbackActivity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _courseColorAccentFor(fallbackActivity);
    final palette = blackbookPalette(context);
    final background = _accentBackgroundFor(context, accent);
    final foreground = _accentForegroundFor(context, accent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: foreground.withValues(alpha: 0.22)),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  colorKey == null ? '课程颜色：自动匹配' : '课程颜色：${accent.label}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: palette.muted, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseColorPickerSheet extends StatelessWidget {
  const _CourseColorPickerSheet({
    required this.currentColorKey,
    required this.fallbackActivity,
  });

  final String? currentColorKey;
  final CourseActivity fallbackActivity;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final autoAccent = _courseColorAccentFor(fallbackActivity);
    final palette = blackbookPalette(context);
    return FractionallySizedBox(
      heightFactor: 0.44,
      alignment: Alignment.bottomCenter,
      widthFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.handle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '课程颜色',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView(
                    physics: const ClampingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 78,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.70,
                        ),
                    children: [
                      _CourseColorChoiceTile(
                        label: '自动',
                        accent: autoAccent,
                        selected: currentColorKey == null,
                        onTap: () => Navigator.of(context).pop(''),
                      ),
                      for (final accent in _courseAccentOptions)
                        _CourseColorChoiceTile(
                          label: accent.label,
                          accent: accent,
                          selected: currentColorKey == accent.key,
                          onTap: () => Navigator.of(context).pop(accent.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseColorChoiceTile extends StatelessWidget {
  const _CourseColorChoiceTile({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final _CourseAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final accentBackground = _accentBackgroundFor(context, accent);
    final accentForeground = _accentForegroundFor(context, accent);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accentBackground,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? accentForeground.withValues(alpha: 0.62)
                          : accentForeground.withValues(alpha: 0.22),
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check, size: 13, color: accentForeground),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? accentForeground : palette.subtle,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: selected ? 22 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseNatureEditor extends StatelessWidget {
  const _CourseNatureEditor({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(Icons.category_outlined, color: palette.primary, size: 25),
          const SizedBox(width: 18),
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: '必修', label: Text('必修')),
                ButtonSegment<String>(value: '选修', label: Text('选修')),
              ],
              selected: {value.contains('选') ? '选修' : '必修'},
              onSelectionChanged: (values) => onChanged(values.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return palette.onPrimary;
                  }
                  return palette.subtle;
                }),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return palette.primary;
                  }
                  return palette.surfaceAlt;
                }),
                side: WidgetStatePropertyAll(
                  BorderSide(color: palette.divider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseProgramEditor extends StatelessWidget {
  const _CourseProgramEditor({required this.value, required this.onChanged});

  final CourseProgramType value;
  final ValueChanged<CourseProgramType> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(Icons.school_outlined, color: palette.primary, size: 25),
          const SizedBox(width: 18),
          Expanded(
            child: SegmentedButton<CourseProgramType>(
              segments: const [
                ButtonSegment<CourseProgramType>(
                  value: CourseProgramType.primary,
                  label: Text('主修'),
                ),
                ButtonSegment<CourseProgramType>(
                  value: CourseProgramType.minor,
                  label: Text('辅修'),
                ),
              ],
              selected: {value},
              onSelectionChanged: (values) => onChanged(values.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? palette.onPrimary
                      : palette.subtle;
                }),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? palette.primary
                      : palette.surfaceAlt;
                }),
                side: WidgetStatePropertyAll(
                  BorderSide(color: palette.divider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseEditResult {
  const _CourseEditResult(this.activities);

  final List<CourseActivity> activities;
}

class _EditableCourseTimeSlot {
  _EditableCourseTimeSlot({
    required this.weeksController,
    required this.weekdayController,
    required this.startUnitController,
    required this.endUnitController,
    required this.startTimeController,
    required this.endTimeController,
    required this.roomController,
  });

  final TextEditingController weeksController;
  final TextEditingController weekdayController;
  final TextEditingController startUnitController;
  final TextEditingController endUnitController;
  final TextEditingController startTimeController;
  final TextEditingController endTimeController;
  final TextEditingController roomController;

  factory _EditableCourseTimeSlot.fromActivity(
    CourseActivity? activity,
    _CourseEditorPage page,
  ) {
    return _EditableCourseTimeSlot(
      weeksController: TextEditingController(
        text: activity?.weeksText ?? page.selectedWeek.toString(),
      ),
      weekdayController: TextEditingController(
        text: (activity?.weekday ?? DateTime.now().weekday).toString(),
      ),
      startUnitController: TextEditingController(
        text: (activity?.startUnit ?? 1).toString(),
      ),
      endUnitController: TextEditingController(
        text: (activity?.endUnit ?? 2).toString(),
      ),
      startTimeController: TextEditingController(
        text: activity?.startTime ?? '08:00',
      ),
      endTimeController: TextEditingController(
        text: activity?.endTime ?? '09:35',
      ),
      roomController: TextEditingController(text: activity?.room ?? ''),
    );
  }

  void dispose() {
    weeksController.dispose();
    weekdayController.dispose();
    startUnitController.dispose();
    endUnitController.dispose();
    startTimeController.dispose();
    endTimeController.dispose();
    roomController.dispose();
  }
}

class _CourseTimeSlotEditor extends StatelessWidget {
  const _CourseTimeSlotEditor({
    required this.slot,
    required this.index,
    required this.canRemove,
    required this.onRemove,
  });

  final _EditableCourseTimeSlot slot;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '时间段 ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '删除时间段',
                onPressed: canRemove ? onRemove : null,
                color: palette.subtle,
                disabledColor: palette.muted,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          _EditorField(
            icon: Icons.calendar_today_outlined,
            color: const Color(0xFF19B6A6),
            controller: slot.weeksController,
            label: '周次，如 1-16 或 1-16 Odd',
          ),
          _EditorField(
            icon: Icons.schedule_outlined,
            color: const Color(0xFFFFB12F),
            controller: slot.weekdayController,
            label: '星期，1-7',
            keyboardType: TextInputType.number,
          ),
          Row(
            children: [
              Expanded(
                child: _EditorField(
                  icon: Icons.view_day_outlined,
                  color: const Color(0xFFFFB12F),
                  controller: slot.startUnitController,
                  label: '开始节',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EditorField(
                  icon: Icons.view_day_outlined,
                  color: const Color(0xFFFFB12F),
                  controller: slot.endUnitController,
                  label: '结束节',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _EditorField(
                  icon: Icons.access_time,
                  color: const Color(0xFFFFB12F),
                  controller: slot.startTimeController,
                  label: '开始时间',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EditorField(
                  icon: Icons.access_time,
                  color: const Color(0xFFFFB12F),
                  controller: slot.endTimeController,
                  label: '结束时间',
                ),
              ),
            ],
          ),
          _EditorField(
            icon: Icons.meeting_room_outlined,
            color: const Color(0xFFFF4D4D),
            controller: slot.roomController,
            label: '地点',
          ),
        ],
      ),
    );
  }
}

enum _CourseDetailAction { copy, edit, delete }

class _DetailMoreButton extends StatelessWidget {
  const _DetailMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Tooltip(
      message: '更多',
      child: IconButton(
        onPressed: onPressed,
        iconSize: 24,
        color: palette.primary,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        icon: const Icon(Icons.more_horiz),
      ),
    );
  }
}

class _CourseDetailActionsSheet extends StatelessWidget {
  const _CourseDetailActionsSheet();

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final border = Theme.of(context).brightness == Brightness.dark
        ? null
        : Border.all(color: palette.divider);
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomPadding),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius: BorderRadius.circular(18),
              border: border,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CourseDetailActionTile(
                    icon: Icons.copy_all_outlined,
                    label: '复制信息',
                    color: palette.primary,
                    action: _CourseDetailAction.copy,
                  ),
                  _CourseDetailActionTile(
                    icon: Icons.edit_outlined,
                    label: '编辑课程',
                    color: palette.primary,
                    action: _CourseDetailAction.edit,
                  ),
                  _CourseDetailActionTile(
                    icon: Icons.delete_outline,
                    label: '删除课程',
                    color: palette.danger,
                    action: _CourseDetailAction.delete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseDetailActionTile extends StatelessWidget {
  const _CourseDetailActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.action,
  });

  final IconData icon;
  final String label;
  final Color color;
  final _CourseDetailAction action;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).pop(action),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: label.contains('删除') ? color : palette.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = blackbookPalette(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 6),
          SizedBox(
            width: 78,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.subtle,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaidOutActivity {
  const _LaidOutActivity({
    required this.group,
    required this.weekday,
    required this.startUnit,
    required this.endUnit,
  });

  final _CourseConflictGroup group;
  final int weekday;
  final int startUnit;
  final int endUnit;
}

class _WeekLayout {
  const _WeekLayout({required this.items, required this.maxUnit});

  final List<_LaidOutActivity> items;
  final int maxUnit;
}

class _CourseConflictGroup {
  const _CourseConflictGroup({
    required this.activities,
    required this.selectedActivity,
    required this.groupKey,
    required this.outOfWeek,
  });

  final List<CourseActivity> activities;
  final CourseActivity selectedActivity;
  final String groupKey;
  final bool outOfWeek;

  bool get hasConflict => activities.length > 1;
}

class _UnitSpan {
  const _UnitSpan(this.start, this.end);

  final int start;
  final int end;

  bool overlaps(_UnitSpan other) {
    return start <= other.end && other.start <= end;
  }
}

class _ConflictChoiceUpdate {
  const _ConflictChoiceUpdate({
    required this.weekIndex,
    required this.groupKey,
    required this.selectedActivityKey,
  });

  final int weekIndex;
  final String groupKey;
  final String selectedActivityKey;
}

class _CourseAccent {
  const _CourseAccent({
    required this.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String key;
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
}

const _courseAccentOptions = [
  _CourseAccent(
    key: 'computer',
    label: '计算机',
    background: Color(0xFFE3F2FF),
    foreground: Color(0xFF1675B7),
    icon: Icons.desktop_windows_outlined,
  ),
  _CourseAccent(
    key: 'ai_data',
    label: 'AI数据',
    background: Color(0xFFEAF8F4),
    foreground: Color(0xFF119982),
    icon: Icons.show_chart_outlined,
  ),
  _CourseAccent(
    key: 'math',
    label: '数理',
    background: Color(0xFFF0EEFF),
    foreground: Color(0xFF7358C8),
    icon: Icons.functions_outlined,
  ),
  _CourseAccent(
    key: 'physics',
    label: '物理',
    background: Color(0xFFEAF6FF),
    foreground: Color(0xFF1C7EB2),
    icon: Icons.bolt_outlined,
  ),
  _CourseAccent(
    key: 'chemistry',
    label: '化工',
    background: Color(0xFFFFF1DE),
    foreground: Color(0xFFC87516),
    icon: Icons.science_outlined,
  ),
  _CourseAccent(
    key: 'experiment',
    label: '实验',
    background: Color(0xFFFFE9E8),
    foreground: Color(0xFFD45545),
    icon: Icons.science_outlined,
  ),
  _CourseAccent(
    key: 'practice',
    label: '实践',
    background: Color(0xFFEFF6FF),
    foreground: Color(0xFF437AC2),
    icon: Icons.construction_outlined,
  ),
  _CourseAccent(
    key: 'geology',
    label: '地质油气',
    background: Color(0xFFE9F8EF),
    foreground: Color(0xFF218357),
    icon: Icons.terrain_outlined,
  ),
  _CourseAccent(
    key: 'engineering',
    label: '工程',
    background: Color(0xFFF2F1FF),
    foreground: Color(0xFF6856C7),
    icon: Icons.apartment_outlined,
  ),
  _CourseAccent(
    key: 'mechanical',
    label: '机械',
    background: Color(0xFFFFF0EA),
    foreground: Color(0xFFC65D33),
    icon: Icons.precision_manufacturing_outlined,
  ),
  _CourseAccent(
    key: 'materials',
    label: '材料',
    background: Color(0xFFFFF7DF),
    foreground: Color(0xFFB98517),
    icon: Icons.category_outlined,
  ),
  _CourseAccent(
    key: 'environment',
    label: '环境生态',
    background: Color(0xFFE7F8E9),
    foreground: Color(0xFF3D8C43),
    icon: Icons.eco_outlined,
  ),
  _CourseAccent(
    key: 'economy',
    label: '经管',
    background: Color(0xFFFFF2EA),
    foreground: Color(0xFFC46635),
    icon: Icons.account_balance_outlined,
  ),
  _CourseAccent(
    key: 'law',
    label: '法学',
    background: Color(0xFFF0F4FF),
    foreground: Color(0xFF526BC0),
    icon: Icons.gavel_outlined,
  ),
  _CourseAccent(
    key: 'language',
    label: '语言',
    background: Color(0xFFEFF2FF),
    foreground: Color(0xFF5964C8),
    icon: Icons.translate_outlined,
  ),
  _CourseAccent(
    key: 'sports',
    label: '体育',
    background: Color(0xFFEAF8FF),
    foreground: Color(0xFF177EA8),
    icon: Icons.sports_basketball_outlined,
  ),
  _CourseAccent(
    key: 'thinking',
    label: '思政',
    background: Color(0xFFEFF8EF),
    foreground: Color(0xFF247F58),
    icon: Icons.psychology_alt_outlined,
  ),
  _CourseAccent(
    key: 'design',
    label: '设计写作',
    background: Color(0xFFFFEDF6),
    foreground: Color(0xFFC94D83),
    icon: Icons.draw_outlined,
  ),
  _CourseAccent(
    key: 'article',
    label: '论文',
    background: Color(0xFFFFF6E5),
    foreground: Color(0xFFB87719),
    icon: Icons.article_outlined,
  ),
  _CourseAccent(
    key: 'general',
    label: '通识',
    background: Color(0xFFF3F5F9),
    foreground: Color(0xFF59677B),
    icon: Icons.school_outlined,
  ),
];

const _legacyCourseAccentAliases = {
  'book': 'general',
  'biology': 'practice',
  'chart': 'ai_data',
  'building': 'engineering',
  'ecology': 'environment',
  'workshop': 'practice',
  'lab': 'experiment',
};

const _strongCourseAccentRules = [
  _CourseAccentRule('chemistry', [
    '化工原理',
    '化工热力学',
    '化工传递',
    '传递过程',
    '化学反应工程',
    '分离工程',
    '化工设计',
    '化工安全',
    '化工导论',
    '化工过程',
    '化工设备',
    '化学工程',
    '石油加工',
    '石油炼制',
    '催化',
    '反应器',
    '有机化学',
    '无机化学',
    '分析化学',
    '物理化学',
    '普通化学',
    '化学原理',
    '化学',
  ]),
  _CourseAccentRule('math', [
    '概率论',
    '概率统计',
    '数理统计',
    '统计学',
    '高等数学',
    '线性代数',
    '离散数学',
    '数学建模',
    '复变函数',
    '积分变换',
    '微积分',
    '矩阵理论',
    '数学分析',
    '数学物理方法',
    '数理方程',
    '最优化方法',
    '矢量分析',
    '计算方法',
    '数值计算',
    '数值分析',
    '运筹学',
  ]),
  _CourseAccentRule('experiment', [
    '实验',
    '监测实验',
    '物理化学实验',
    '大学物理实验',
    '分析测试',
    '测定',
    '测量',
  ]),
  _CourseAccentRule('physics', [
    '大学物理',
    '物理化学实验',
    '物理化学',
    '物理',
    '力学',
    '电磁',
    '光学',
    '热学',
    '量子',
  ]),
  _CourseAccentRule('computer', [
    '计算机',
    '程序设计',
    '软件',
    '网络',
    '数据库',
    '操作系统',
    '数据结构',
    'c语言',
    'matlab',
    'python',
    'java',
    'web',
    '信息系统',
  ]),
  _CourseAccentRule('ai_data', [
    '机器学习',
    '人工智能',
    '深度学习',
    '统计学习',
    '数据挖掘',
    '大数据',
    '数据分析',
    '数据科学',
    '算法设计',
  ]),
  _CourseAccentRule('mechanical', [
    '机械制图',
    '工程图学',
    '机械',
    '机电',
    '电工',
    '电子',
    '自动化',
    '控制',
    '机器人',
  ]),
  _CourseAccentRule('environment', [
    '环境',
    '生态',
    '污染',
    '碳中和',
    '碳封存',
    '环保',
    '土壤学',
    '微生物学',
  ]),
  _CourseAccentRule('geology', [
    '地质',
    '油气',
    '矿物',
    '岩石',
    '沉积',
    '测井',
    '勘探',
    '地震',
    '构造',
    '地球物理',
    '地理信息',
    '遥感',
  ]),
  _CourseAccentRule('materials', ['材料', '新能源', '储能', '高分子', '金属', '腐蚀', '焊接']),
  _CourseAccentRule('thinking', [
    '思政',
    '毛泽东',
    '马克思',
    '习近平',
    '中国近现代史',
    '思想道德',
    '形势与政策',
  ]),
  _CourseAccentRule('sports', ['体育', '篮球', '足球', '排球', '武术', '健美操', '运动']),
  _CourseAccentRule('language', [
    '大学英语',
    '学术英语',
    '专业英语',
    '英语',
    '俄语',
    '日语',
    '外语',
    '翻译',
    '口语',
    '听力',
  ]),
  _CourseAccentRule('article', ['毕业论文', '毕业设计', '论文']),
  _CourseAccentRule('practice', [
    '实习',
    '实训',
    '实践',
    '课程设计',
    '大作业',
    '创新创业',
    '训练',
  ]),
  _CourseAccentRule('economy', ['经济', '管理', '会计', '财务', '营销', '项目管理', '金融']),
  _CourseAccentRule('law', ['法律', '法学', '知识产权', '法规']),
  _CourseAccentRule('design', ['设计', '写作', '检索', '绘图']),
  _CourseAccentRule('engineering', ['安全工程', '海洋工程', '储运工程', '建筑', '设备']),
];

const _weakCourseAccentRules = [
  _CourseAccentRule('chemistry', ['化工', '化学', '炼制']),
  _CourseAccentRule('math', ['数学', '统计']),
  _CourseAccentRule('computer', ['程序', '编程', '信息']),
  _CourseAccentRule('engineering', ['工程', '工艺', '设备']),
];

class _CourseAccentRule {
  const _CourseAccentRule(this.key, this.keywords);

  final String key;
  final List<String> keywords;

  bool matches(String text) {
    return keywords.any(
      (keyword) => text.contains(_normalizeAccentText(keyword)),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateText(DateTime date) {
  return '${date.year}/${date.month}/${date.day}';
}

String _conflictGroupKey(List<CourseActivity> activities) {
  final keys = activities.map(_activityChoiceKey).toList()..sort();
  return keys.join('|');
}

String _activityChoiceKey(CourseActivity activity) {
  return [
    activity.lessonId,
    activity.lessonCode,
    activity.courseCode,
    activity.weekday,
    activity.startUnit,
    activity.endUnit,
    activity.room,
    activity.teacherText,
  ].join('#');
}

String _shortTeacherName(String value) {
  final text = value.trim();
  if (text.isEmpty || text == '教师未公布') {
    return '';
  }
  final first = text.split(RegExp(r'\s*/\s*')).first.trim();
  final bracket = first.indexOf('(');
  if (bracket > 0) {
    return first.substring(0, bracket).trim();
  }
  return first;
}

String _weekdayChinese(int weekday) {
  const values = ['一', '二', '三', '四', '五', '六', '日'];
  return values[weekday - 1];
}

String _semesterDisplayName(String value) {
  final match = RegExp(r'^(\d{4})-(\d{4})-(\d+)$').firstMatch(value);
  if (match == null) {
    return value;
  }
  final start = match.group(1);
  final end = match.group(2);
  final suffix = match.group(3);
  return '$start-$end学年-$suffix';
}

String _courseClipboardText(CourseActivity activity) {
  final code = activity.lessonCode.isEmpty
      ? activity.courseCode
      : activity.lessonCode;
  return [
    activity.courseName,
    '${activity.credits.toStringAsFixed(1)} 学分 '
        '${activity.courseNature} ${activity.programType.label}',
    '授课教师：${activity.teacherText}',
    '上课地点：${activity.placeText}',
    '周次：第 ${activity.weeksText} 周',
    '节次与时间：第 ${activity.startUnit} - ${activity.endUnit} 节 '
        '${activity.startTime} - ${activity.endTime}',
    if (code.isNotEmpty) '课程代码：$code',
  ].join('\n');
}

_CourseAccent _courseIconAccentFor(CourseActivity activity) {
  final explicit = _courseAccentForKey(activity.iconKey);
  if (explicit != null) {
    return explicit;
  }
  return _automaticCourseAccentFor(activity);
}

_CourseAccent _courseColorAccentFor(CourseActivity activity) {
  final explicit = _courseAccentForKey(activity.colorKey);
  if (explicit != null) {
    return explicit;
  }
  return _automaticCourseAccentFor(activity);
}

_CourseAccent _automaticCourseAccentFor(CourseActivity activity) {
  final primaryText = _primaryAccentSearchText(activity);
  for (final rule in _strongCourseAccentRules) {
    if (rule.matches(primaryText)) {
      return _courseAccentForKey(rule.key) ?? _courseAccentOptions.last;
    }
  }
  final fullText = _fullAccentSearchText(activity);
  for (final rule in _weakCourseAccentRules) {
    if (rule.matches(fullText)) {
      return _courseAccentForKey(rule.key) ?? _courseAccentOptions.last;
    }
  }
  return _courseAccentForKey('general') ?? _courseAccentOptions.last;
}

String _primaryAccentSearchText(CourseActivity activity) {
  final primaryName = activity.courseName.trim().isNotEmpty
      ? activity.courseName
      : activity.lessonName;
  return _normalizeAccentText(primaryName);
}

String _fullAccentSearchText(CourseActivity activity) {
  return _normalizeAccentText(
    [
      activity.courseName,
      activity.lessonName,
      activity.lessonRemark ?? '',
      activity.lessonCode,
      activity.courseCode,
    ].where((value) => value.trim().isNotEmpty).join(' '),
  );
}

String _normalizeAccentText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('（', '(')
      .replaceAll('）', ')');
}

_CourseAccent? _courseAccentForKey(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = _legacyCourseAccentAliases[value] ?? value;
  for (final accent in _courseAccentOptions) {
    if (accent.key == normalized) {
      return accent;
    }
  }
  return null;
}
