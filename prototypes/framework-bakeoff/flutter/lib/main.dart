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
            selectedIndex: selectedNav,
            onSelected: (index) => setState(() => selectedNav = index),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(controller: controller),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _QueuePane(
                                controller: controller,
                                selectedTab: selectedTab,
                                onTabSelected: (index) {
                                  setState(() => selectedTab = index);
                                },
                              ),
                            ),
                            if (constraints.maxWidth >= 900) ...[
                              const SizedBox(width: 18),
                              SizedBox(
                                width: 304,
                                child: _AssistantPanel(controller: controller),
                              ),
                            ],
                          ],
                        );
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
  const _Sidebar({required this.selectedIndex, required this.onSelected});

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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: _LocalSummary(),
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
  const _LocalSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VtColors.surfaceBlue,
        border: Border.all(color: VtColors.cyanSoft),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          SizedBox(height: 7),
          Text(
            'CUDA 已就绪 · medium',
            style: TextStyle(
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
  const _TopBar({required this.controller});

  final WorkbenchController controller;

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
              const Text(
                '工作台',
                style: TextStyle(
                  color: VtColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '本次已完成 ${controller.completedTasks.length} 个音频',
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
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: '更多选项',
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_horiz_rounded, size: 21),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuePane extends StatelessWidget {
  const _QueuePane({
    required this.controller,
    required this.selectedTab,
    required this.onTabSelected,
  });

  final WorkbenchController controller;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;

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
              label: const Text('开始转写'),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
          ),
        ),
      ],
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['任务队列', '转写稿'];
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
  const _RecentOutputs({required this.tasks, required this.onOpenOutput});

  final List<TaskSnapshot> tasks;
  final Future<void> Function([TaskSnapshot? task]) onOpenOutput;

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
                TextButton(onPressed: () {}, child: const Text('查看全部')),
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
            task.completedAt.isEmpty ? '刚刚' : task.completedAt,
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
                    '小樱助手',
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
            height: 190,
            color: VtColors.surfaceSoft,
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  top: 15,
                  child: Text(
                    controller.lastError.isNotEmpty
                        ? '有一项需要处理'
                        : task == null
                        ? '选一个音频开始吧'
                        : controller.running
                        ? '正在本地转写'
                        : '任务已经准备好',
                    style: const TextStyle(
                      color: VtColors.pinkPressed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 6,
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 60,
                    color: VtColors.pink.withValues(alpha: 0.08),
                  ),
                ),
                Positioned.fill(
                  top: 10,
                  child: Semantics(
                    image: true,
                    label: '戴粉色耳机的 Q 版语音助手',
                    child: Image.asset(
                      'assets/assistant.png',
                      alignment: Alignment.bottomCenter,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本次配置',
                  style: TextStyle(
                    color: VtColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 9),
                _SettingRow(label: '识别模型', value: 'Whisper JA 1.5B'),
                _SettingRow(label: '源语言', value: '日语'),
                _SettingRow(label: '输出格式', value: '日语 SRT'),
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
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: VtColors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
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
