import 'dart:async';

import 'package:flutter/material.dart';

import 'workbench_controller.dart';

void main() {
  runApp(const VoiceTranslApp());
}

abstract final class VtColors {
  static const background = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFFFF3F7);
  static const surfaceBlue = Color(0xFFF0FAFC);
  static const border = Color(0xFFE5E7EB);
  static const borderStrong = Color(0xFFD4D8DE);
  static const ink = Color(0xFF24262B);
  static const inkMuted = Color(0xFF686D76);
  static const inkFaint = Color(0xFF9297A1);
  static const pink = Color(0xFFE9578A);
  static const pinkPressed = Color(0xFFD9457A);
  static const pinkSoft = Color(0xFFFDE3EC);
  static const cyan = Color(0xFF2AA7B8);
  static const cyanSoft = Color(0xFFDFF5F7);
  static const green = Color(0xFF3B9B72);
  static const greenSoft = Color(0xFFE4F4EC);
  static const amber = Color(0xFFB7791F);
  static const amberSoft = Color(0xFFFFF3D6);
}

class VoiceTranslApp extends StatelessWidget {
  const VoiceTranslApp({super.key, this.demoMode = false, this.controller});

  final bool demoMode;
  final WorkbenchController? controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: VtColors.pink,
          brightness: Brightness.light,
          surface: VtColors.surface,
        ).copyWith(
          primary: VtColors.pink,
          onPrimary: Colors.white,
          secondary: VtColors.cyan,
          onSecondary: Colors.white,
          outline: VtColors.borderStrong,
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VoiceTransl ASMR',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: VtColors.background,
        fontFamily: 'Microsoft YaHei UI',
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: VtColors.ink,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleMedium: TextStyle(
            color: VtColors.ink,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          bodyMedium: TextStyle(
            color: VtColors.ink,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
          bodySmall: TextStyle(
            color: VtColors.inkMuted,
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
          labelLarge: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: VtColors.border,
          thickness: 1,
          space: 1,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: VtColors.ink,
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 0,
          ),
          waitDuration: const Duration(milliseconds: 450),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: VtColors.inkMuted,
            minimumSize: const Size(40, 40),
            maximumSize: const Size(40, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: VtColors.pink,
            foregroundColor: Colors.white,
            disabledBackgroundColor: VtColors.border,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: VtColors.ink,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            side: const BorderSide(color: VtColors.borderStrong),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
      ),
      home: RepaintBoundary(
        key: const ValueKey('app-canvas'),
        child: WorkbenchPage(demoMode: demoMode, controller: controller),
      ),
    );
  }
}

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, this.demoMode = false, this.controller});

  final bool demoMode;
  final WorkbenchController? controller;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

enum _QuickAction { addFiles, scanDirectory, openProject, settings }

class _WorkbenchPageState extends State<WorkbenchPage> {
  int selectedNav = 0;
  int selectedTab = 0;
  late final WorkbenchController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        (widget.demoMode ? WorkbenchController.demo() : WorkbenchController());
    controller.addListener(_handleControllerChanged);
    if (!widget.demoMode) {
      unawaited(controller.initialize());
    }
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String get _pageTitle =>
      const ['工作台', '素材库', '词汇表', '导出记录', '设置'][selectedNav];

  String get _pageSubtitle => switch (selectedNav) {
    0 => '已有 ${controller.completedTasks.length} 个可用输出',
    1 => '已载入 ${controller.tasks.length} 个本地音视频文件',
    2 => '维护转写纠错、翻译术语和译后替换',
    3 => '已持久化 ${controller.completedTasks.length} 条处理记录',
    _ => controller.workerReady ? 'Python 后端已连接' : 'Python 后端当前离线',
  };

  void _selectNavigation(int index) {
    setState(() => selectedNav = index);
  }

  void _handleQuickAction(_QuickAction action) {
    switch (action) {
      case _QuickAction.addFiles:
        unawaited(controller.pickFiles());
      case _QuickAction.scanDirectory:
        unawaited(controller.pickDirectory());
      case _QuickAction.openProject:
        unawaited(controller.openProjectDirectory());
      case _QuickAction.settings:
        _selectNavigation(4);
    }
  }

  void _showActivityDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final entries = controller.logs.isEmpty
            ? [controller.statusText]
            : controller.logs.reversed.take(100).toList(growable: false);
        return AlertDialog(
          key: const ValueKey('activity-dialog'),
          title: const Row(
            children: [
              Icon(Icons.notifications_none_rounded, size: 20),
              SizedBox(width: 10),
              Text('运行记录'),
            ],
          ),
          content: SizedBox(
            width: 620,
            height: 360,
            child: ListView.separated(
              itemCount: entries.length,
              itemBuilder: (context, index) => SelectableText(
                entries[index],
                style: const TextStyle(
                  color: VtColors.inkMuted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              separatorBuilder: (context, index) => const Divider(height: 18),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPage(BoxConstraints constraints) => switch (selectedNav) {
    0 => Row(
      key: const ValueKey('workbench-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _QueuePane(
            controller: controller,
            selectedTab: selectedTab,
            onTabSelected: (index) => setState(() => selectedTab = index),
            onViewAll: () => _selectNavigation(3),
          ),
        ),
        if (constraints.maxWidth >= 900) ...[
          const SizedBox(width: 18),
          SizedBox(width: 304, child: _AssistantPanel(controller: controller)),
        ],
      ],
    ),
    1 => _MediaLibraryPage(controller: controller),
    2 => _DictionaryPage(controller: controller),
    3 => _ExportHistoryPage(controller: controller),
    _ => _SettingsPage(controller: controller),
  };

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    if (ownsController) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            controller: controller,
            selectedIndex: selectedNav,
            onSelected: _selectNavigation,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  controller: controller,
                  title: _pageTitle,
                  subtitle: _pageSubtitle,
                  onNotifications: _showActivityDialog,
                  onQuickAction: _handleQuickAction,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildPage(constraints);
                      },
                    ),
                  ),
                ),
                _StatusBar(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.selectedIndex,
    required this.onSelected,
  });

  final WorkbenchController controller;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.space_dashboard_outlined, '工作台'),
      (Icons.audio_file_outlined, '素材库'),
      (Icons.menu_book_outlined, '词汇表'),
      (Icons.outbox_outlined, '导出记录'),
    ];

    return Container(
      width: 206,
      decoration: const BoxDecoration(
        color: VtColors.surface,
        border: Border(right: BorderSide(color: VtColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: _Brand(),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '项目',
              style: TextStyle(
                color: VtColors.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: _NavItem(
                icon: items[index].$1,
                label: items[index].$2,
                selected: index == selectedIndex,
                onTap: () => onSelected(index),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _LocalSummary(controller: controller),
          ),
          const SizedBox(height: 12),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: _NavItem(
              icon: Icons.settings_outlined,
              label: '设置',
              selected: selectedIndex == 4,
              onTap: () => onSelected(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: VtColors.pink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VoiceTransl',
                maxLines: 1,
                style: TextStyle(
                  color: VtColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'ASMR 字幕工坊',
                maxLines: 1,
                style: TextStyle(
                  color: VtColors.inkMuted,
                  fontSize: 11,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? VtColors.pinkSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  icon,
                  size: 20,
                  color: selected ? VtColors.pinkPressed : VtColors.inkMuted,
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? VtColors.pinkPressed : VtColors.ink,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: VtColors.pink,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalSummary extends StatelessWidget {
  const _LocalSummary({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VtColors.surfaceBlue,
        border: Border.all(color: VtColors.cyanSoft),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.memory_outlined, size: 17, color: VtColors.cyan),
              SizedBox(width: 7),
              Text(
                '本地推理',
                style: TextStyle(
                  color: VtColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              Spacer(),
              _Dot(color: VtColors.green),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${controller.localComputeLabel} · ${controller.transcriptionIntensityLabel}强度',
            style: const TextStyle(
              color: VtColors.inkMuted,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.onNotifications,
    required this.onQuickAction,
  });

  final WorkbenchController controller;
  final String title;
  final String subtitle;
  final VoidCallback onNotifications;
  final ValueChanged<_QuickAction> onQuickAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: VtColors.surface,
        border: Border(bottom: BorderSide(color: VtColors.border)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: VtColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: VtColors.inkMuted,
                  fontSize: 11,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const Spacer(),
          _StatusChip(
            label: controller.workerReady ? '本地后端' : '后端离线',
            icon: Icons.shield_outlined,
            foreground: controller.workerReady
                ? VtColors.green
                : VtColors.amber,
            background: controller.workerReady
                ? VtColors.greenSoft
                : VtColors.amberSoft,
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: '通知',
            child: IconButton(
              onPressed: onNotifications,
              icon: const Icon(Icons.notifications_none_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_QuickAction>(
            tooltip: '更多选项',
            icon: const Icon(Icons.more_horiz_rounded, size: 21),
            onSelected: onQuickAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _QuickAction.addFiles,
                child: _MenuRow(icon: Icons.add_rounded, label: '添加音频'),
              ),
              PopupMenuItem(
                value: _QuickAction.scanDirectory,
                child: _MenuRow(
                  icon: Icons.folder_open_outlined,
                  label: '扫描目录',
                ),
              ),
              PopupMenuItem(
                value: _QuickAction.openProject,
                child: _MenuRow(icon: Icons.source_outlined, label: '打开项目目录'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _QuickAction.settings,
                child: _MenuRow(icon: Icons.settings_outlined, label: '设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: VtColors.inkMuted),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _QueuePane extends StatelessWidget {
  const _QueuePane({
    required this.controller,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onViewAll,
  });

  final WorkbenchController controller;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SegmentedTabs(
              selectedIndex: selectedTab,
              onSelected: onTabSelected,
            ),
            const Spacer(),
            Tooltip(
              message: '扫描输入目录',
              child: OutlinedButton.icon(
                onPressed: controller.running ? null : controller.pickDirectory,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('扫描目录'),
              ),
            ),
            const SizedBox(width: 9),
            OutlinedButton.icon(
              onPressed: controller.running ? null : controller.pickFiles,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('添加音频'),
            ),
            const SizedBox(width: 9),
            FilledButton.icon(
              onPressed: controller.canStart ? controller.startTasks : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 19),
              label: Text(
                controller.translationEnabled ? '转写并翻译' : '开始转写',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: selectedTab == 0
              ? Column(
                  key: const ValueKey('queue-page'),
                  children: [
                    _ActiveTask(
                      task: controller.activeTask,
                      running: controller.running,
                      onCancel: controller.cancel,
                      onOpenOutput: controller.openOutput,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _RecentOutputs(
                        tasks: controller.completedTasks,
                        onOpenOutput: controller.openOutput,
                        onViewAll: onViewAll,
                      ),
                    ),
                  ],
                )
              : _TranscriptPage(controller: controller),
        ),
      ],
    );
  }
}

class _TranscriptPage extends StatelessWidget {
  const _TranscriptPage({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final completed = controller.completedTasks;
    return Container(
      key: const ValueKey('transcript-page'),
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Row(
              children: [
                const Text(
                  '字幕预览',
                  style: TextStyle(
                    color: VtColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    controller.transcriptSource.isEmpty
                        ? '选择一个历史任务读取 SRT'
                        : controller.transcriptSource,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VtColors.inkFaint,
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '重新加载字幕',
                  onPressed: completed.isEmpty
                      ? null
                      : () => unawaited(controller.loadTranscript()),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
          ),
          const Divider(),
          if (completed.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: completed.length,
                itemBuilder: (context, index) {
                  final task = completed[index];
                  return OutlinedButton.icon(
                    onPressed: () => unawaited(controller.loadTranscript(task)),
                    icon: const Icon(Icons.subtitles_outlined, size: 16),
                    label: Text(task.name),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 8),
              ),
            ),
          if (completed.isNotEmpty) const Divider(),
          Expanded(
            child: controller.transcriptPreview.isEmpty
                ? const _PageEmptyState(
                    icon: Icons.subtitles_outlined,
                    title: '还没有可预览的字幕',
                    message: '完成任务后，可在这里读取日语或双语 SRT 内容',
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      controller.transcriptPreview,
                      style: const TextStyle(
                        color: VtColors.ink,
                        fontSize: 13,
                        height: 1.65,
                        fontFamily: 'Microsoft YaHei UI',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MediaLibraryPage extends StatelessWidget {
  const _MediaLibraryPage({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('media-library-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SummaryMetric(
              label: '全部素材',
              value: '${controller.tasks.length}',
              icon: Icons.audio_file_outlined,
            ),
            const SizedBox(width: 10),
            _SummaryMetric(
              label: '等待处理',
              value:
                  '${controller.tasks.where((task) => !task.isFinished).length}',
              icon: Icons.schedule_rounded,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: controller.running || controller.tasks.isEmpty
                  ? null
                  : controller.clearTasks,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('清空'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: controller.running ? null : controller.pickDirectory,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('扫描目录'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: controller.running ? null : controller.pickFiles,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加音频'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: VtColors.surface,
              border: Border.all(color: VtColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: controller.tasks.isEmpty
                ? const _PageEmptyState(
                    icon: Icons.library_music_outlined,
                    title: '素材库为空',
                    message: '添加音频或扫描本地目录后，文件会在这里统一管理',
                  )
                : ListView.separated(
                    itemCount: controller.tasks.length,
                    itemBuilder: (context, index) {
                      final task = controller.tasks[index];
                      return SizedBox(
                        height: 72,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.audio_file_outlined,
                                color: VtColors.pink,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: VtColors.ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      task.path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: VtColors.inkFaint,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 150,
                                child: LinearProgressIndicator(
                                  value: task.progress,
                                  minHeight: 5,
                                  borderRadius: BorderRadius.circular(3),
                                  color: VtColors.pink,
                                  backgroundColor: VtColors.pinkSoft,
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 78,
                                child: _StatusChip(
                                  label: task.statusLabel,
                                  foreground: _taskStatusForeground(task),
                                  background: _taskStatusBackground(task),
                                ),
                              ),
                              if (task.hasOutput)
                                IconButton(
                                  tooltip: '打开输出',
                                  onPressed: () => controller.openOutput(task),
                                  icon: const Icon(
                                    Icons.folder_open_outlined,
                                    size: 18,
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: '移除素材',
                                  onPressed: controller.running
                                      ? null
                                      : () => controller.removeTask(task),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (context, index) => const Divider(),
                  ),
          ),
        ),
      ],
    );
  }
}

class _DictionaryPage extends StatelessWidget {
  const _DictionaryPage({required this.controller});

  final WorkbenchController controller;

  static const entries = [
    (
      '转写纠错词典',
      '修正常见 ASR 错字、角色名和社团名',
      'dictionaries/transcription_corrections.txt',
      Icons.hearing_outlined,
    ),
    (
      '翻译术语表',
      '固定人物、关系和重复概念的中文译法',
      'dictionaries/translation_glossary.txt',
      Icons.translate_rounded,
    ),
    (
      '译后替换词典',
      '对翻译结果执行确定性的最终替换',
      'dictionaries/post_translation_replacements.txt',
      Icons.find_replace_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('dictionary-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '本地词典文件',
              style: TextStyle(
                color: VtColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () =>
                  controller.openWorkspaceDirectory('dictionaries'),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('打开词典目录'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final entry in entries) ...[
          Container(
            height: 104,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: VtColors.surface,
              border: Border.all(color: VtColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: VtColors.pinkSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(entry.$4, color: VtColors.pinkPressed, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$1,
                        style: const TextStyle(
                          color: VtColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        entry.$2,
                        style: const TextStyle(
                          color: VtColors.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.$3,
                        style: const TextStyle(
                          color: VtColors.inkFaint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showWorkspaceTextEditor(
                    context,
                    controller: controller,
                    title: entry.$1,
                    description: entry.$2,
                    relativePath: entry.$3,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('应用内编辑'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ExportHistoryPage extends StatelessWidget {
  const _ExportHistoryPage({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final tasks = controller.completedTasks;
    return Container(
      key: const ValueKey('export-history-page'),
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 12, 11),
            child: Row(
              children: [
                Text(
                  '历史输出 · ${tasks.length}',
                  style: const TextStyle(
                    color: VtColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: controller.openProjectDirectory,
                  icon: const Icon(Icons.source_outlined, size: 17),
                  label: const Text('项目目录'),
                ),
              ],
            ),
          ),
          const Divider(),
          const _OutputHeader(),
          const Divider(),
          Expanded(
            child: tasks.isEmpty
                ? const _PageEmptyState(
                    icon: Icons.outbox_outlined,
                    title: '还没有导出记录',
                    message: '完成的日语与双语 SRT 会跨启动保留在这里',
                  )
                : ListView.separated(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) => SizedBox(
                      height: 74,
                      child: _OutputRow(
                        task: tasks[index],
                        onOpenOutput: controller.openOutput,
                      ),
                    ),
                    separatorBuilder: (context, index) => const Divider(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings-page'),
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: VtColors.surface,
            border: Border.all(color: VtColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _Dot(
                color: controller.workerReady ? VtColors.green : VtColors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.workerReady ? 'Python 后端已连接' : 'Python 后端离线',
                      style: const TextStyle(
                        color: VtColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.lastError.isEmpty
                          ? controller.projectRootPath
                          : controller.lastError,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VtColors.inkMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.running
                    ? null
                    : controller.reconnectWorker,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(controller.workerReady ? '检查连接' : '重新连接'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RuntimeModePanel(controller: controller),
        const SizedBox(height: 10),
        _TranscriptionModelPanel(controller: controller),
        const SizedBox(height: 10),
        _SettingsActionRow(
          icon: Icons.translate_rounded,
          title: '翻译模型',
          subtitle:
              '${controller.translationModel} · ${controller.translationEndpoint} · '
              '${controller.apiKeyConfigured ? '密钥已配置' : '未配置密钥'}',
          actionLabel: '配置接口',
          onPressed:
              controller.workerReady &&
                  !controller.running &&
                  !controller.configurationBusy
              ? () => _showTranslationConfigDialog(
                  context,
                  controller: controller,
                )
              : null,
        ),
        const SizedBox(height: 10),
        _SettingsActionRow(
          icon: Icons.tune_rounded,
          title: '高级配置文件',
          subtitle: 'VAD、字幕合并、质量检查与模型路径',
          actionLabel: '编辑 YAML',
          onPressed: () => _showWorkspaceTextEditor(
            context,
            controller: controller,
            title: '高级配置文件',
            description: '直接编辑 settings.yaml，保存后对下一批任务生效',
            relativePath: 'settings.yaml',
          ),
        ),
        const SizedBox(height: 10),
        _SettingsActionRow(
          icon: Icons.memory_rounded,
          title: '本地模型',
          subtitle: '转写模型和 ASMR VAD 均从项目 models 目录读取',
          actionLabel: '打开模型目录',
          onPressed: () => controller.openWorkspaceDirectory('models'),
        ),
        const SizedBox(height: 10),
        _SettingsActionRow(
          icon: Icons.folder_copy_outlined,
          title: '项目目录',
          subtitle: controller.projectRootPath,
          actionLabel: '在资源管理器中打开',
          onPressed: controller.openProjectDirectory,
        ),
      ],
    );
  }
}

class _RuntimeModePanel extends StatelessWidget {
  const _RuntimeModePanel({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 14, 13),
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '运行模式',
                      style: TextStyle(
                        color: VtColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '控制下一批任务是否调用翻译接口并生成双语字幕',
                      style: TextStyle(color: VtColors.inkMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.hearing_rounded, size: 17),
                    label: Text('仅转写'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.translate_rounded, size: 17),
                    label: Text('转写 + 翻译'),
                  ),
                ],
                selected: {controller.translationEnabled},
                showSelectedIcon: false,
                onSelectionChanged: controller.running
                    ? null
                    : (selection) => unawaited(
                        controller.setTranslationEnabled(selection.first),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Divider(),
          _CompactSwitchRow(
            title: '复用缓存',
            subtitle: '已有中间结果可直接复用，适合日常重复处理',
            value: controller.reuseCache,
            enabled: !controller.running,
            onChanged: (value) => unawaited(controller.setReuseCache(value)),
          ),
          _CompactSwitchRow(
            title: '翻译接口预检',
            subtitle: '任务开始前检查接口配置，避免转写后才发现不可用',
            value: controller.apiPreflight,
            enabled: controller.translationEnabled && !controller.running,
            onChanged: (value) => unawaited(controller.setApiPreflight(value)),
          ),
        ],
      ),
    );
  }
}

class _TranscriptionModelPanel extends StatelessWidget {
  const _TranscriptionModelPanel({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final detail = switch (controller.transcriptionIntensity) {
      'low' => '快速 · beam 1',
      'high' => '精细 · beam 8',
      _ => '均衡 · beam 5',
    };
    final enabled =
        controller.workerReady &&
        !controller.running &&
        !controller.configurationBusy;
    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: VtColors.cyanSoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: VtColors.cyan,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本地转写强度',
                  style: TextStyle(
                    color: VtColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'TransWithAI Whisper JA 1.5B',
                  style: TextStyle(color: VtColors.inkMuted, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  '${controller.localComputeLabel} · $detail',
                  style: const TextStyle(color: VtColors.inkFaint, fontSize: 10),
                ),
              ],
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'low', label: Text('低')),
              ButtonSegment(value: 'medium', label: Text('中')),
              ButtonSegment(value: 'high', label: Text('高')),
            ],
            selected: {controller.transcriptionIntensity},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (selection) => unawaited(
                    controller.setTranscriptionIntensity(selection.first),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _CompactSwitchRow extends StatelessWidget {
  const _CompactSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? VtColors.ink : VtColors.inkFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VtColors.inkMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

Future<void> _showTranslationConfigDialog(
  BuildContext context, {
  required WorkbenchController controller,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TranslationConfigDialog(controller: controller),
  );
}

class _TranslationConfigDialog extends StatefulWidget {
  const _TranslationConfigDialog({required this.controller});

  final WorkbenchController controller;

  @override
  State<_TranslationConfigDialog> createState() =>
      _TranslationConfigDialogState();
}

class _TranslationConfigDialogState extends State<_TranslationConfigDialog> {
  late final TextEditingController endpointController;
  late final TextEditingController modelController;
  final TextEditingController apiKeyController = TextEditingController();
  bool obscureApiKey = true;
  bool saving = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    endpointController = TextEditingController(
      text: widget.controller.translationEndpoint,
    );
    modelController = TextEditingController(
      text: widget.controller.translationModel,
    );
  }

  Future<void> _save() async {
    final endpoint = endpointController.text.trim();
    final model = modelController.text.trim();
    final apiKey = apiKeyController.text.trim();
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() => error = '请输入以 http:// 或 https:// 开头的 API 地址');
      return;
    }
    if (model.isEmpty) {
      setState(() => error = '模型名称不能为空');
      return;
    }
    if (!widget.controller.apiKeyConfigured && apiKey.isEmpty) {
      setState(() => error = '首次配置需要填写 API key');
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await widget.controller.saveTranslationConfiguration(
        endpoint: endpoint,
        model: model,
        apiKey: apiKey.isEmpty ? null : apiKey,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = exception.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    endpointController.dispose();
    modelController.dispose();
    apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('translation-config-dialog'),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: VtColors.pinkSoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.translate_rounded,
              size: 19,
              color: VtColors.pinkPressed,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(child: Text('OpenAI 兼容翻译')),
          IconButton(
            tooltip: '关闭',
            onPressed: saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '用于 OpenAI、DeepSeek、LM Studio、Ollama 等兼容接口',
              style: TextStyle(color: VtColors.inkMuted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('translation-endpoint-field'),
              controller: endpointController,
              enabled: !saving,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'API 基础地址',
                hintText: 'http://127.0.0.1:8000 或 https://api.openai.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('translation-model-field'),
              controller: modelController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: '例如 gpt-4.1-mini 或本地模型 ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('translation-api-key-field'),
              controller: apiKeyController,
              enabled: !saving,
              obscureText: obscureApiKey,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: widget.controller.apiKeyConfigured
                    ? '已配置，留空保持原密钥'
                    : '请输入 API key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: obscureApiKey ? '显示密钥' : '隐藏密钥',
                  onPressed: () => setState(
                    () => obscureApiKey = !obscureApiKey,
                  ),
                  icon: Icon(
                    obscureApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: VtColors.cyan),
                SizedBox(width: 6),
                Text(
                  '密钥只写入项目 .env，界面不会回显已保存值',
                  style: TextStyle(color: VtColors.inkMuted, fontSize: 10),
                ),
              ],
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VtColors.pinkPressed, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: saving
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 17),
          label: Text(saving ? '保存中' : '保存配置'),
        ),
      ],
    );
  }
}

Future<void> _showWorkspaceTextEditor(
  BuildContext context, {
  required WorkbenchController controller,
  required String title,
  required String description,
  required String relativePath,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _WorkspaceTextEditorDialog(
      controller: controller,
      title: title,
      description: description,
      relativePath: relativePath,
    ),
  );
}

class _WorkspaceTextEditorDialog extends StatefulWidget {
  const _WorkspaceTextEditorDialog({
    required this.controller,
    required this.title,
    required this.description,
    required this.relativePath,
  });

  final WorkbenchController controller;
  final String title;
  final String description;
  final String relativePath;

  @override
  State<_WorkspaceTextEditorDialog> createState() =>
      _WorkspaceTextEditorDialogState();
}

class _WorkspaceTextEditorDialogState
    extends State<_WorkspaceTextEditorDialog> {
  final TextEditingController textController = TextEditingController();
  bool loading = true;
  bool saving = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      textController.text = await widget.controller.readWorkspaceText(
        widget.relativePath,
      );
    } catch (exception) {
      error = exception.toString();
    }
    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await widget.controller.saveWorkspaceText(
        widget.relativePath,
        textController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = exception.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('workspace-editor-dialog'),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: VtColors.pinkSoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              size: 20,
              color: VtColors.pinkPressed,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(widget.title)),
          IconButton(
            tooltip: '关闭',
            onPressed: saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: const TextStyle(color: VtColors.inkMuted, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              widget.relativePath,
              style: const TextStyle(color: VtColors.inkFaint, fontSize: 10),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : TextField(
                      key: const ValueKey('workspace-editor-field'),
                      controller: textController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        color: VtColors.ink,
                        fontSize: 12,
                        height: 1.55,
                        fontFamily: 'Consolas',
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: VtColors.background,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: VtColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: VtColors.border),
                        ),
                      ),
                    ),
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VtColors.pinkPressed, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: loading || saving ? null : _save,
          icon: saving
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 17),
          label: Text(saving ? '保存中' : '保存'),
        ),
      ],
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: VtColors.pinkPressed, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: VtColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VtColors.inkMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: VtColors.inkMuted),
          const SizedBox(width: 7),
          Text(
            '$label  ',
            style: const TextStyle(color: VtColors.inkMuted, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
              color: VtColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageEmptyState extends StatelessWidget {
  const _PageEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: VtColors.pink),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: VtColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VtColors.inkMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['任务队列', '字幕预览'];
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEAECF0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < labels.length; index++)
            Material(
              color: selectedIndex == index
                  ? VtColors.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 78,
                  alignment: Alignment.center,
                  decoration: selectedIndex == index
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: VtColors.border),
                        )
                      : null,
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      color: selectedIndex == index
                          ? VtColors.ink
                          : VtColors.inkMuted,
                      fontSize: 12,
                      fontWeight: selectedIndex == index
                          ? FontWeight.w600
                          : FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveTask extends StatelessWidget {
  const _ActiveTask({
    required this.task,
    required this.running,
    required this.onCancel,
    required this.onOpenOutput,
  });

  final TaskSnapshot? task;
  final bool running;
  final VoidCallback onCancel;
  final Future<void> Function([TaskSnapshot? task]) onOpenOutput;

  @override
  Widget build(BuildContext context) {
    final task = this.task;
    if (task == null) {
      return const _EmptyTaskCard();
    }
    return Container(
      height: 246,
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: VtColors.pinkSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.multitrack_audio_outlined,
                    size: 21,
                    color: VtColors.pinkPressed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VtColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '日语 · Whisper JA 1.5B · 本地转写',
                        maxLines: 1,
                        style: const TextStyle(
                          color: VtColors.inkMuted,
                          fontSize: 11,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(
                  label: task.statusLabel,
                  icon: task.status == 'running'
                      ? Icons.graphic_eq_rounded
                      : task.hasOutput
                      ? Icons.check_rounded
                      : Icons.schedule_rounded,
                  foreground: _taskStatusForeground(task),
                  background: _taskStatusBackground(task),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      task.stage,
                      style: const TextStyle(
                        color: VtColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(task.progress * 100).round()}%',
                      style: const TextStyle(
                        color: VtColors.pinkPressed,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 6,
                    backgroundColor: VtColors.pinkSoft,
                    valueColor: const AlwaysStoppedAnimation(VtColors.pink),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: VtColors.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.format_quote_rounded,
                  size: 17,
                  color: VtColors.pink,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.error.isNotEmpty ? task.error : task.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VtColors.inkMuted,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 12, 12),
            child: Row(
              children: [
                const _InlineMeta(
                  icon: Icons.lock_outline_rounded,
                  label: '仅本地处理',
                ),
                const SizedBox(width: 15),
                _InlineMeta(
                  icon: Icons.layers_outlined,
                  label: '总体进度 ${(task.progress * 100).round()}%',
                ),
                const Spacer(),
                if (running)
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('停止'),
                    style: TextButton.styleFrom(
                      foregroundColor: VtColors.inkMuted,
                      minimumSize: const Size(0, 38),
                    ),
                  )
                else if (task.hasOutput)
                  TextButton.icon(
                    onPressed: () => onOpenOutput(task),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('打开输出'),
                    style: TextButton.styleFrom(
                      foregroundColor: VtColors.inkMuted,
                      minimumSize: const Size(0, 38),
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

class _EmptyTaskCard extends StatelessWidget {
  const _EmptyTaskCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 246,
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audio_file_outlined, size: 32, color: VtColors.pink),
            SizedBox(height: 10),
            Text(
              '还没有待处理的音频',
              style: TextStyle(
                color: VtColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '添加文件或扫描目录后即可开始本地转写',
              style: TextStyle(
                color: VtColors.inkMuted,
                fontSize: 11,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _taskStatusForeground(TaskSnapshot task) => switch (task.status) {
  'running' => VtColors.cyan,
  'success' || 'transcribe_only' => VtColors.green,
  'translation_failed' => VtColors.amber,
  'failed' || 'cancelled' => VtColors.inkMuted,
  _ => VtColors.inkMuted,
};

Color _taskStatusBackground(TaskSnapshot task) => switch (task.status) {
  'running' => VtColors.cyanSoft,
  'success' || 'transcribe_only' => VtColors.greenSoft,
  'translation_failed' => VtColors.amberSoft,
  'failed' || 'cancelled' => VtColors.background,
  _ => VtColors.background,
};

class _RecentOutputs extends StatelessWidget {
  const _RecentOutputs({
    required this.tasks,
    required this.onOpenOutput,
    required this.onViewAll,
  });

  final List<TaskSnapshot> tasks;
  final Future<void> Function([TaskSnapshot? task]) onOpenOutput;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 10, 11),
            child: Row(
              children: [
                const Text(
                  '最近输出',
                  style: TextStyle(
                    color: VtColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${tasks.length} 个文件',
                  style: const TextStyle(
                    color: VtColors.inkFaint,
                    fontSize: 11,
                    letterSpacing: 0,
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onViewAll, child: const Text('查看全部')),
              ],
            ),
          ),
          const Divider(),
          const _OutputHeader(),
          const Divider(),
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Text(
                      '完成的字幕会出现在这里',
                      style: TextStyle(
                        color: VtColors.inkMuted,
                        fontSize: 11,
                        letterSpacing: 0,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) => SizedBox(
                      height: 74,
                      child: _OutputRow(
                        task: tasks[index],
                        onOpenOutput: onOpenOutput,
                      ),
                    ),
                    separatorBuilder: (context, index) => const Padding(
                      padding: EdgeInsets.only(left: 18),
                      child: Divider(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OutputHeader extends StatelessWidget {
  const _OutputHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: VtColors.inkFaint,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    return const SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(width: 18),
          Expanded(flex: 5, child: Text('文件', style: style)),
          Expanded(flex: 2, child: Text('格式', style: style)),
          Expanded(flex: 2, child: Text('时间', style: style)),
          SizedBox(width: 78, child: Text('状态', style: style)),
          SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({required this.task, required this.onOpenOutput});

  final TaskSnapshot task;
  final Future<void> Function([TaskSnapshot? task]) onOpenOutput;

  @override
  Widget build(BuildContext context) {
    final needsReview = task.status == 'translation_failed';
    return Row(
      children: [
        const SizedBox(width: 18),
        Expanded(
          flex: 5,
          child: Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 17,
                color: VtColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VtColors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            task.format,
            style: const TextStyle(
              color: VtColors.inkMuted,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            task.completedLabel,
            style: const TextStyle(
              color: VtColors.inkMuted,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(
          width: 78,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _StatusChip(
              label: needsReview ? '需校对' : task.statusLabel,
              foreground: needsReview ? VtColors.amber : VtColors.green,
              background: needsReview ? VtColors.amberSoft : VtColors.greenSoft,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Tooltip(
            message: '打开文件位置',
            child: IconButton(
              onPressed: () => onOpenOutput(task),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final task = controller.activeTask;
    const stageOrder = ['', 'audio', 'vad', 'asr', 'translate', 'quality'];
    final currentStage = stageOrder.indexOf(task?.stageKey ?? '');

    _ActivityState stateFor(int stage) {
      if (task == null) {
        return _ActivityState.pending;
      }
      if (task.isFinished || currentStage > stage) {
        return _ActivityState.complete;
      }
      if (currentStage == stage && task.status == 'running') {
        return _ActivityState.active;
      }
      return _ActivityState.pending;
    }

    return Container(
      decoration: BoxDecoration(
        color: VtColors.surface,
        border: Border.all(color: VtColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    '声纹助手',
                    style: TextStyle(
                      color: VtColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(),
                  _Dot(
                    color: controller.workerReady
                        ? VtColors.green
                        : VtColors.amber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    controller.workerReady ? '在线' : '离线',
                    style: const TextStyle(
                      color: VtColors.inkMuted,
                      fontSize: 11,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Container(
            height: 158,
            color: VtColors.surfaceSoft,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.lastError.isNotEmpty
                      ? '有一项需要处理'
                      : task == null
                      ? '选一个音频开始吧'
                      : controller.running
                      ? controller.translationEnabled
                            ? '正在生成双语字幕'
                            : '正在本地转写'
                      : '任务已经准备好',
                  style: const TextStyle(
                    color: VtColors.pinkPressed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const Spacer(),
                const Align(
                  alignment: Alignment.center,
                  child: _VoiceMark(),
                ),
                const Spacer(),
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    'MIMI · LOCAL VOICE LAB',
                    style: TextStyle(
                      color: VtColors.inkMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本次配置',
                  style: TextStyle(
                    color: VtColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 9),
                const _SettingRow(label: '识别模型', value: 'Whisper JA 1.5B'),
                _SettingRow(
                  label: '转写强度',
                  value: controller.transcriptionIntensityLabel,
                ),
                _SettingRow(
                  label: '翻译模型',
                  value: controller.translationEnabled
                      ? controller.translationModel
                      : '已关闭',
                ),
                _SettingRow(
                  label: '输出格式',
                  value: controller.translationEnabled ? '双语 SRT' : '日语 SRT',
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '处理记录',
                    style: TextStyle(
                      color: VtColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActivityLine(
                    label: '音频预处理',
                    time: stateFor(1) == _ActivityState.complete ? '完成' : '等待中',
                    state: stateFor(1),
                  ),
                  const SizedBox(height: 8),
                  _ActivityLine(
                    label: '生成日语时间轴',
                    time: stateFor(3) == _ActivityState.active
                        ? '进行中'
                        : stateFor(3) == _ActivityState.complete
                        ? '完成'
                        : '等待中',
                    state: stateFor(3),
                  ),
                  const SizedBox(height: 8),
                  _ActivityLine(
                    label: '翻译中文字幕',
                    time: !controller.translationEnabled
                        ? '已关闭'
                        : stateFor(4) == _ActivityState.active
                        ? '进行中'
                        : stateFor(4) == _ActivityState.complete
                        ? '完成'
                        : '等待中',
                    state: !controller.translationEnabled
                        ? _ActivityState.pending
                        : stateFor(4),
                  ),
                  const SizedBox(height: 8),
                  _ActivityLine(
                    label: '写入字幕文件',
                    time: task?.hasOutput == true ? '完成' : '等待中',
                    state: task?.hasOutput == true
                        ? _ActivityState.complete
                        : _ActivityState.pending,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 15),
            child: OutlinedButton.icon(
              onPressed: task?.hasOutput == true
                  ? () => controller.openOutput(task)
                  : null,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('打开输出文件夹'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceMark extends StatelessWidget {
  const _VoiceMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '粉色声纹助手标识',
      child: Container(
        key: const ValueKey('voice-mark'),
        width: 76,
        height: 68,
        decoration: BoxDecoration(
          color: VtColors.surface,
          border: Border.all(color: const Color(0xFFF4B6CC), width: 1.5),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1AE9578A),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 42,
                color: VtColors.pink,
              ),
            ),
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: VtColors.cyanSoft,
                  border: Border.all(color: VtColors.surface, width: 2),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 13,
                  color: VtColors.cyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 27,
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: VtColors.inkMuted,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: VtColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ActivityState { complete, active, pending }

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({
    required this.label,
    required this.time,
    required this.state,
  });

  final String label;
  final String time;
  final _ActivityState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _ActivityState.complete => VtColors.green,
      _ActivityState.active => VtColors.pink,
      _ActivityState.pending => VtColors.inkFaint,
    };
    final icon = switch (state) {
      _ActivityState.complete => Icons.check_circle_rounded,
      _ActivityState.active => Icons.radio_button_checked_rounded,
      _ActivityState.pending => Icons.radio_button_unchecked_rounded,
    };

    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: state == _ActivityState.pending
                  ? VtColors.inkMuted
                  : VtColors.ink,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
        ),
        Text(
          time,
          style: const TextStyle(
            color: VtColors.inkFaint,
            fontSize: 10,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 9 : 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  const _InlineMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: VtColors.inkFaint),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: VtColors.inkMuted,
            fontSize: 10,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: VtColors.surface,
        border: Border(top: BorderSide(color: VtColors.border)),
      ),
      child: Row(
        children: [
          _Dot(color: controller.workerReady ? VtColors.green : VtColors.amber),
          const SizedBox(width: 7),
          Text(
            controller.statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VtColors.inkMuted,
              fontSize: 10,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 15),
          Text(
            '队列 ${controller.tasks.where((task) => !task.isFinished).length}',
            style: const TextStyle(
              color: VtColors.inkMuted,
              fontSize: 10,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          const Text(
            'VoiceTransl 0.1 · Flutter Desktop Study',
            style: TextStyle(
              color: VtColors.inkFaint,
              fontSize: 10,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
