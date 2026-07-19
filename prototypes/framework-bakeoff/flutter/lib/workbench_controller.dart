import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'worker_client.dart';

const _mediaExtensions = {
  'aac',
  'avi',
  'flac',
  'm4a',
  'mkv',
  'mov',
  'mp3',
  'mp4',
  'ogg',
  'wav',
};

const _editableWorkspaceFiles = {
  'settings.yaml',
  'dictionaries/transcription_corrections.txt',
  'dictionaries/translation_glossary.txt',
  'dictionaries/post_translation_replacements.txt',
};

abstract interface class MediaPicker {
  Future<List<String>> pickFiles();

  Future<List<String>> pickDirectory();
}

abstract interface class WorkspaceLauncher {
  Future<void> openDirectory(String path);

  Future<void> openFile(String path);
}

class NativeWorkspaceLauncher implements WorkspaceLauncher {
  @override
  Future<void> openDirectory(String path) async {
    await Process.start('explorer.exe', [path], runInShell: false);
  }

  @override
  Future<void> openFile(String path) async {
    await Process.start('notepad.exe', [path], runInShell: false);
  }
}

class NativeMediaPicker implements MediaPicker {
  static const XTypeGroup _mediaTypes = XTypeGroup(
    label: '音频和视频',
    extensions: [..._mediaExtensions],
  );

  @override
  Future<List<String>> pickFiles() async {
    final files = await openFiles(acceptedTypeGroups: const [_mediaTypes]);
    return files.map((file) => file.path).toList(growable: false);
  }

  @override
  Future<List<String>> pickDirectory() async {
    final directoryPath = await getDirectoryPath();
    if (directoryPath == null) {
      return const [];
    }
    final entries = Directory(directoryPath).listSync(followLinks: false);
    return entries
        .whereType<File>()
        .where((file) => _mediaExtensions.contains(_extension(file.path)))
        .map((file) => file.path)
        .toList(growable: false)
      ..sort();
  }
}

class TaskSnapshot {
  const TaskSnapshot({
    required this.path,
    required this.name,
    this.status = 'queued',
    this.stage = '等待开始',
    this.stageKey = '',
    this.progress = 0,
    this.outputDir = '',
    this.error = '',
    this.warnings = 0,
    this.completedAt = '',
    this.format = 'SRT',
  });

  final String path;
  final String name;
  final String status;
  final String stage;
  final String stageKey;
  final double progress;
  final String outputDir;
  final String error;
  final int warnings;
  final String completedAt;
  final String format;

  bool get isFinished => const {
    'success',
    'transcribe_only',
    'translation_failed',
    'failed',
    'cancelled',
  }.contains(status);

  bool get hasOutput =>
      outputDir.isNotEmpty &&
      const {
        'success',
        'transcribe_only',
        'translation_failed',
      }.contains(status);

  String get completedLabel {
    final timestamp = DateTime.tryParse(completedAt)?.toLocal();
    if (timestamp == null) {
      return completedAt.isEmpty ? '刚刚' : completedAt;
    }
    final now = DateTime.now();
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final today = DateTime(now.year, now.month, now.day);
    final time = '${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}';
    if (day == today) {
      return '今天 $time';
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return '昨天 $time';
    }
    return '${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} $time';
  }

  String get statusLabel => switch (status) {
    'running' => '转写中',
    'success' => '已完成',
    'transcribe_only' => '已完成',
    'translation_failed' => '翻译失败',
    'failed' => '失败',
    'cancelled' => '已取消',
    _ => '等待中',
  };

  TaskSnapshot copyWith({
    String? status,
    String? stage,
    String? stageKey,
    double? progress,
    String? outputDir,
    String? error,
    int? warnings,
    String? completedAt,
    String? format,
  }) {
    return TaskSnapshot(
      path: path,
      name: name,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      stageKey: stageKey ?? this.stageKey,
      progress: progress ?? this.progress,
      outputDir: outputDir ?? this.outputDir,
      error: error ?? this.error,
      warnings: warnings ?? this.warnings,
      completedAt: completedAt ?? this.completedAt,
      format: format ?? this.format,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'status': status,
    'stage': stage,
    'stage_key': stageKey,
    'progress': progress,
    'output_dir': outputDir,
    'error': error,
    'warnings': warnings,
    'completed_at': completedAt,
    'format': format,
  };

  factory TaskSnapshot.fromJson(Map<String, dynamic> json) {
    return TaskSnapshot(
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'transcribe_only',
      stage: json['stage']?.toString() ?? '处理完成',
      stageKey: json['stage_key']?.toString() ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 1,
      outputDir: json['output_dir']?.toString() ?? '',
      error: json['error']?.toString() ?? '',
      warnings: (json['warnings'] as num?)?.toInt() ?? 0,
      completedAt: json['completed_at']?.toString() ?? '',
      format: json['format']?.toString() ?? 'SRT',
    );
  }
}

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    WorkerTransport? worker,
    MediaPicker? mediaPicker,
    WorkspaceLauncher? workspaceLauncher,
    Directory? projectRoot,
  }) : _worker = worker ?? VoiceTranslWorkerClient(),
       _mediaPicker = mediaPicker ?? NativeMediaPicker(),
       _workspaceLauncher = workspaceLauncher ?? NativeWorkspaceLauncher(),
       _projectRoot = projectRoot ?? _findProjectRoot();

  WorkbenchController.demo()
    : _worker = null,
      _mediaPicker = NativeMediaPicker(),
      _workspaceLauncher = NativeWorkspaceLauncher(),
      _projectRoot = Directory.current,
      workerReady = true,
      running = true,
      statusText = '正在转写日语音频',
      tasks = const [
        TaskSnapshot(
          path: r'D:\ASMR\RJ01423376_track01.wav',
          name: 'RJ01423376_track01.wav',
          status: 'running',
          stage: '日语语音转写',
          stageKey: 'asr',
          progress: 0.68,
        ),
        TaskSnapshot(
          path: r'D:\ASMR\RJ01422108_part02.wav',
          name: 'RJ01422108_part02.wav',
          status: 'transcribe_only',
          stage: '处理完成',
          progress: 1,
          outputDir: r'D:\ASMR\RJ01422108_part02.voicetransl',
          completedAt: '今天 14:32',
        ),
        TaskSnapshot(
          path: r'D:\ASMR\RJ01399842_track03.flac',
          name: 'RJ01399842_track03.flac',
          status: 'transcribe_only',
          stage: '处理完成',
          progress: 1,
          outputDir: r'D:\ASMR\RJ01399842_track03.voicetransl',
          completedAt: '今天 13:18',
        ),
        TaskSnapshot(
          path: r'D:\ASMR\RJ01387016_bonus.mp3',
          name: 'RJ01387016_bonus.mp3',
          status: 'translation_failed',
          stage: '需要校对',
          progress: 1,
          outputDir: r'D:\ASMR\RJ01387016_bonus.voicetransl',
          completedAt: '昨天 22:46',
        ),
      ];

  final WorkerTransport? _worker;
  final MediaPicker _mediaPicker;
  final WorkspaceLauncher _workspaceLauncher;
  final Directory _projectRoot;
  StreamSubscription<Map<String, dynamic>>? _workerSubscription;
  String? _activeRequestId;
  List<int> _requestTaskIndices = const [];
  List<TaskSnapshot> _history = const [];
  bool _workspaceStateLoaded = false;

  bool workerReady = false;
  bool running = false;
  bool translationEnabled = true;
  bool reuseCache = true;
  bool apiPreflight = true;
  String statusText = '正在连接 Python 后端';
  String lastError = '';
  String transcriptPreview = '';
  String transcriptSource = '';
  List<TaskSnapshot> tasks = const [];
  final List<String> logs = [];

  bool get canStart =>
      workerReady && tasks.any((task) => !task.isFinished) && !running;

  TaskSnapshot? get activeTask {
    for (final task in tasks) {
      if (task.status == 'running') {
        return task;
      }
    }
    for (final task in tasks) {
      if (!task.isFinished) {
        return task;
      }
    }
    return tasks.isEmpty ? null : tasks.first;
  }

  List<TaskSnapshot> get completedTasks {
    final completed = <TaskSnapshot>[];
    final seen = <String>{};
    for (final task in [
      ..._history,
      ...tasks.where((task) => task.hasOutput),
    ]) {
      final key = (task.outputDir.isEmpty ? task.path : task.outputDir)
          .toLowerCase();
      if (seen.add(key)) {
        completed.add(task);
      }
    }
    return completed;
  }

  String get projectRootPath => _projectRoot.path;

  double get overallProgress {
    if (tasks.isEmpty) {
      return 0;
    }
    return tasks.fold<double>(0, (total, task) => total + task.progress) /
        tasks.length;
  }

  Future<void> initialize() async {
    if (!_workspaceStateLoaded) {
      await Future.wait([_loadPreferences(), _loadHistory()]);
      _workspaceStateLoaded = true;
      notifyListeners();
    }
    final worker = _worker;
    if (worker == null) {
      return;
    }
    _workerSubscription ??= worker.messages.listen(_handleWorkerMessage);
    try {
      await worker.start();
    } catch (error) {
      workerReady = false;
      lastError = error.toString();
      statusText = 'Python 后端启动失败';
      notifyListeners();
    }
  }

  Future<void> pickFiles() async {
    await _pick(_mediaPicker.pickFiles);
  }

  Future<void> pickDirectory() async {
    await _pick(_mediaPicker.pickDirectory);
  }

  void removeTask(TaskSnapshot task) {
    if (running) {
      return;
    }
    tasks = tasks.where((item) => item.path != task.path).toList();
    statusText = tasks.isEmpty ? '任务列表已清空' : '已移除 ${task.name}';
    notifyListeners();
  }

  void clearTasks() {
    if (running || tasks.isEmpty) {
      return;
    }
    tasks = const [];
    transcriptPreview = '';
    transcriptSource = '';
    statusText = '任务列表已清空';
    notifyListeners();
  }

  Future<void> setTranslationEnabled(bool value) async {
    if (translationEnabled == value || running) {
      return;
    }
    translationEnabled = value;
    statusText = value ? '已启用转写与翻译' : '已切换为仅转写';
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setReuseCache(bool value) async {
    if (reuseCache == value || running) {
      return;
    }
    reuseCache = value;
    statusText = value ? '将优先复用已有缓存' : '下次任务将重新处理';
    await _savePreferences();
    notifyListeners();
  }

  Future<void> setApiPreflight(bool value) async {
    if (apiPreflight == value || running) {
      return;
    }
    apiPreflight = value;
    statusText = value ? '翻译前将检查接口连接' : '已跳过翻译接口预检';
    await _savePreferences();
    notifyListeners();
  }

  Future<void> reconnectWorker() async {
    if (_worker == null || running) {
      return;
    }
    if (workerReady) {
      lastError = '';
      statusText = 'Python 后端连接正常';
      notifyListeners();
      return;
    }
    workerReady = false;
    lastError = '';
    statusText = '正在重新连接 Python 后端';
    notifyListeners();
    await initialize();
  }

  Future<void> _pick(Future<List<String>> Function() picker) async {
    if (running) {
      return;
    }
    try {
      final paths = await picker();
      _addPaths(paths);
    } catch (error) {
      lastError = error.toString();
      statusText = '读取本地文件失败';
      notifyListeners();
    }
  }

  void _addPaths(List<String> paths) {
    final existing = {for (final task in tasks) task.path.toLowerCase()};
    final additions = <TaskSnapshot>[];
    for (final path in paths) {
      final key = path.toLowerCase();
      if (!existing.add(key) || !_mediaExtensions.contains(_extension(path))) {
        continue;
      }
      additions.add(TaskSnapshot(path: path, name: _basename(path)));
    }
    if (additions.isEmpty) {
      return;
    }
    tasks = [...tasks.where((task) => task.isFinished), ...additions];
    statusText = '已添加 ${additions.length} 个音频文件';
    lastError = '';
    notifyListeners();
  }

  Future<void> startTasks() async {
    final worker = _worker;
    if (!canStart || worker == null) {
      return;
    }
    running = true;
    statusText = translationEnabled ? '正在提交转写与翻译任务' : '正在提交转写任务';
    lastError = '';
    tasks = [
      for (final task in tasks)
        if (task.isFinished)
          task
        else
          task.copyWith(
            status: 'queued',
            stage: '等待 Python 后端',
            stageKey: '',
            progress: 0,
            error: '',
          ),
    ];
    _requestTaskIndices = [
      for (var index = 0; index < tasks.length; index++)
        if (!tasks[index].isFinished) index,
    ];
    notifyListeners();
    try {
      _activeRequestId = await worker.run(
        inputs: [for (final index in _requestTaskIndices) tasks[index].path],
        options: {
          'transcribe_only': !translationEnabled,
          'reuse_cache': reuseCache,
          'skip_api_preflight': !apiPreflight,
        },
      );
    } catch (error) {
      running = false;
      lastError = error.toString();
      statusText = '任务提交失败';
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!running || _worker == null) {
      return;
    }
    statusText = '正在等待安全停止点';
    notifyListeners();
    try {
      await _worker.cancel(_activeRequestId);
    } catch (error) {
      lastError = error.toString();
      statusText = '取消请求发送失败';
      notifyListeners();
    }
  }

  Future<void> openOutput([TaskSnapshot? task]) async {
    final target = task ?? activeTask;
    if (target == null || target.outputDir.isEmpty) {
      return;
    }
    await _workspaceLauncher.openDirectory(target.outputDir);
  }

  Future<void> openProjectDirectory() async {
    await _workspaceLauncher.openDirectory(_projectRoot.path);
  }

  Future<void> openWorkspaceDirectory(String relativePath) async {
    final directory = Directory(_joinPath(_projectRoot.path, relativePath));
    if (!directory.existsSync()) {
      lastError = '目录不存在：${directory.path}';
      statusText = '无法打开目录';
      notifyListeners();
      return;
    }
    await _workspaceLauncher.openDirectory(directory.path);
  }

  Future<void> openWorkspaceFile(String relativePath) async {
    final file = File(_joinPath(_projectRoot.path, relativePath));
    if (!file.existsSync()) {
      lastError = '文件不存在：${file.path}';
      statusText = '无法打开文件';
      notifyListeners();
      return;
    }
    await _workspaceLauncher.openFile(file.path);
  }

  Future<String> readWorkspaceText(String relativePath) async {
    final normalized = relativePath.replaceAll('\\', '/');
    if (!_editableWorkspaceFiles.contains(normalized)) {
      throw ArgumentError.value(relativePath, 'relativePath', '不允许编辑该文件');
    }
    final file = File(_joinPath(_projectRoot.path, normalized));
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', file.path);
    }
    return file.readAsString();
  }

  Future<void> saveWorkspaceText(String relativePath, String content) async {
    final normalized = relativePath.replaceAll('\\', '/');
    if (!_editableWorkspaceFiles.contains(normalized)) {
      throw ArgumentError.value(relativePath, 'relativePath', '不允许编辑该文件');
    }
    final file = File(_joinPath(_projectRoot.path, normalized));
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', file.path);
    }
    await file.writeAsString(content, flush: true);
    lastError = '';
    statusText = '已保存 ${_basename(normalized)}';
    notifyListeners();
  }

  Future<void> loadTranscript([TaskSnapshot? task]) async {
    final completed = completedTasks;
    final target = task ?? (completed.isEmpty ? null : completed.first);
    if (target == null || target.outputDir.isEmpty) {
      transcriptPreview = '';
      transcriptSource = '';
      notifyListeners();
      return;
    }
    final dot = target.name.lastIndexOf('.');
    final stem = dot > 0 ? target.name.substring(0, dot) : target.name;
    final candidates = translationEnabled
        ? ['$stem.combine.srt', '$stem.zh.srt', '$stem.ja.srt']
        : ['$stem.ja.srt', '$stem.combine.srt', '$stem.zh.srt'];
    File? transcript;
    for (final name in candidates) {
      final candidate = File(_joinPath(target.outputDir, name));
      if (candidate.existsSync()) {
        transcript = candidate;
        break;
      }
    }
    final transcriptFile =
        transcript ?? File(_joinPath(target.outputDir, candidates.first));
    if (!transcriptFile.existsSync()) {
      transcriptPreview = '';
      transcriptSource = transcriptFile.path;
      lastError = '找不到字幕文件：${transcriptFile.path}';
      statusText = '字幕尚未生成';
      notifyListeners();
      return;
    }
    transcriptPreview = await transcriptFile.readAsString();
    transcriptSource = transcriptFile.path;
    lastError = '';
    statusText = '已加载 ${target.name} 的字幕';
    notifyListeners();
  }

  void _handleWorkerMessage(Map<String, dynamic> message) {
    final type = message['type'];
    switch (type) {
      case 'ready':
        workerReady = true;
        statusText = tasks.isEmpty ? '后端已连接，请添加音频' : '后端已连接';
        lastError = '';
      case 'accepted':
        running = true;
        statusText = '任务已进入处理队列';
      case 'event':
        final event = message['event'];
        if (event is Map) {
          _applyPipelineEvent(Map<String, dynamic>.from(event));
        }
      case 'completed':
        _applyCompletion(message);
      case 'cancel_requested':
        statusText = '取消已请求，正在安全停止';
      case 'error':
      case 'rejected':
      case 'protocol_error':
        _applyError(message['message']?.toString() ?? '未知后端错误');
      case 'worker_exit':
        workerReady = false;
        running = false;
        statusText = 'Python 后端已退出';
        lastError = '退出代码：${message['exit_code']}';
      case 'log':
        final line = message['message']?.toString();
        if (line != null && line.isNotEmpty) {
          logs.add(line);
          if (logs.length > 200) {
            logs.removeRange(0, logs.length - 200);
          }
        }
    }
    notifyListeners();
  }

  void _applyPipelineEvent(Map<String, dynamic> event) {
    final eventType = event['type'];
    final requestIndex = (event['file_index'] as num?)?.toInt();
    if (eventType == 'batch_started') {
      statusText = '开始处理 ${event['file_count']} 个文件';
      return;
    }
    if (requestIndex == null ||
        requestIndex < 0 ||
        requestIndex >= _requestTaskIndices.length) {
      return;
    }
    final index = _requestTaskIndices[requestIndex];
    final task = tasks[index];
    switch (eventType) {
      case 'file_started':
        _replaceTask(
          index,
          task.copyWith(status: 'running', stage: '准备音频', progress: 0),
        );
        statusText = '正在处理 ${task.name}';
      case 'stage_started':
        final stageIndex = (event['stage_index'] as num?)?.toInt() ?? 1;
        final stageCount = (event['stage_count'] as num?)?.toInt() ?? 1;
        final stageKey = event['stage']?.toString() ?? '';
        _replaceTask(
          index,
          task.copyWith(
            status: 'running',
            stage: _stageLabel(stageKey),
            stageKey: stageKey,
            progress: ((stageIndex - 1) / stageCount).clamp(0, 1),
          ),
        );
        statusText = '${task.name} · ${_stageLabel(stageKey)}';
      case 'stage_progress':
        final stageIndex = (event['stage_index'] as num?)?.toInt() ?? 1;
        final stageCount = (event['stage_count'] as num?)?.toInt() ?? 1;
        final stageProgress = (event['progress'] as num?)?.toDouble() ?? 0;
        _replaceTask(
          index,
          task.copyWith(
            status: 'running',
            progress: (((stageIndex - 1) + stageProgress) / stageCount).clamp(
              0,
              1,
            ),
          ),
        );
      case 'stage_finished':
        final stageIndex = (event['stage_index'] as num?)?.toInt() ?? 1;
        final stageCount = (event['stage_count'] as num?)?.toInt() ?? 1;
        _replaceTask(
          index,
          task.copyWith(progress: (stageIndex / stageCount).clamp(0, 1)),
        );
      case 'file_finished':
        final status = event['status']?.toString() ?? 'failed';
        _replaceTask(
          index,
          task.copyWith(
            status: status,
            stage: status == 'cancelled' ? '已安全停止' : '处理完成',
            progress: status == 'cancelled' ? task.progress : 1,
            outputDir: event['output_dir']?.toString() ?? '',
            error: event['error']?.toString() ?? '',
            warnings: (event['warnings'] as num?)?.toInt() ?? 0,
            completedAt: DateTime.now().toIso8601String(),
            format: status == 'success' ? '双语 SRT' : '日语 SRT',
          ),
        );
    }
  }

  void _applyCompletion(Map<String, dynamic> message) {
    final results = message['results'];
    if (results is List) {
      for (final rawResult in results) {
        if (rawResult is! Map) {
          continue;
        }
        final result = Map<String, dynamic>.from(rawResult);
        final inputPath = result['input_path']?.toString();
        final index = tasks.indexWhere((task) => task.path == inputPath);
        if (index < 0) {
          continue;
        }
        final status = result['status']?.toString() ?? 'failed';
        _replaceTask(
          index,
          tasks[index].copyWith(
            status: status,
            stage: status == 'cancelled' ? '已安全停止' : '处理完成',
            progress: status == 'cancelled' ? tasks[index].progress : 1,
            outputDir: result['output_dir']?.toString() ?? '',
            error: result['error']?.toString() ?? '',
            warnings: (result['warnings'] as num?)?.toInt() ?? 0,
            completedAt: DateTime.now().toIso8601String(),
            format: status == 'success' ? '双语 SRT' : '日语 SRT',
          ),
        );
      }
    }
    final cancelled = message['cancelled'] == true;
    running = false;
    _activeRequestId = null;
    _requestTaskIndices = const [];
    statusText = cancelled ? '任务已取消' : '本批任务处理完成';
    _recordHistory();
    if (!cancelled && completedTasks.isNotEmpty) {
      unawaited(loadTranscript(completedTasks.first));
    }
  }

  void _applyError(String message) {
    running = false;
    lastError = message;
    statusText = '处理失败';
    final index = tasks.indexWhere(
      (task) => task.status == 'running' || !task.isFinished,
    );
    if (index >= 0) {
      _replaceTask(
        index,
        tasks[index].copyWith(status: 'failed', stage: '处理失败', error: message),
      );
    }
  }

  void _replaceTask(int index, TaskSnapshot task) {
    tasks = [...tasks]..[index] = task;
  }

  void _recordHistory() {
    final latest = tasks.where((task) => task.hasOutput).toList();
    if (latest.isEmpty) {
      return;
    }
    final replacedKeys = {
      for (final task in latest)
        (task.outputDir.isEmpty ? task.path : task.outputDir).toLowerCase(),
    };
    _history = [
      ...latest.reversed,
      ..._history.where(
        (task) => !replacedKeys.contains(
          (task.outputDir.isEmpty ? task.path : task.outputDir).toLowerCase(),
        ),
      ),
    ];
    unawaited(_saveHistory());
  }

  Future<void> _loadPreferences() async {
    final file = _preferencesFile;
    if (!await file.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return;
      }
      translationEnabled = decoded['translation_enabled'] as bool? ?? true;
      reuseCache = decoded['reuse_cache'] as bool? ?? true;
      apiPreflight = decoded['api_preflight'] as bool? ?? true;
    } catch (error) {
      logs.add('读取 GUI 偏好失败：$error');
    }
  }

  Future<void> _savePreferences() async {
    final file = _preferencesFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'translation_enabled': translationEnabled,
        'reuse_cache': reuseCache,
        'api_preflight': apiPreflight,
      }),
      flush: true,
    );
  }

  Future<void> _loadHistory() async {
    final restored = <TaskSnapshot>[];
    final file = _historyFile;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final task = TaskSnapshot.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (task.hasOutput && Directory(task.outputDir).existsSync()) {
                restored.add(task);
              }
            }
          }
        }
      } catch (error) {
        logs.add('读取历史索引失败：$error');
      }
    }

    final discovered = _discoverProjectHistory();
    final seen = <String>{};
    _history = [
      ...restored,
      ...discovered,
    ].where((task) {
      final key = task.outputDir.toLowerCase();
      return key.isNotEmpty && seen.add(key);
    }).toList()
      ..sort((left, right) => right.completedAt.compareTo(left.completedAt));
    if (_history.isNotEmpty) {
      await _saveHistory();
    }
  }

  List<TaskSnapshot> _discoverProjectHistory() {
    final mediaDirectory = Directory(_joinPath(_projectRoot.path, 'files'));
    if (!mediaDirectory.existsSync()) {
      return const [];
    }
    final entries = mediaDirectory.listSync(followLinks: false);
    final media = entries
        .whereType<File>()
        .where((file) => _mediaExtensions.contains(_extension(file.path)))
        .toList();
    final history = <TaskSnapshot>[];
    for (final directory in entries.whereType<Directory>()) {
      final directoryName = _basename(directory.path);
      if (!directoryName.endsWith('.voicetransl')) {
        continue;
      }
      final stem = directoryName.substring(
        0,
        directoryName.length - '.voicetransl'.length,
      );
      final subtitles = directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => _extension(file.path) == 'srt')
          .toList();
      if (subtitles.isEmpty) {
        continue;
      }
      subtitles.sort(
        (left, right) => right.lastModifiedSync().compareTo(
          left.lastModifiedSync(),
        ),
      );
      File? source;
      for (final candidate in media) {
        final candidateName = _basename(candidate.path);
        final dot = candidateName.lastIndexOf('.');
        if ((dot > 0 ? candidateName.substring(0, dot) : candidateName) == stem) {
          source = candidate;
          break;
        }
      }
      final bilingual = subtitles.any(
        (file) => file.path.endsWith('.combine.srt') || file.path.endsWith('.zh.srt'),
      );
      history.add(
        TaskSnapshot(
          path: source?.path ?? _joinPath(mediaDirectory.path, stem),
          name: source == null ? stem : _basename(source.path),
          status: bilingual ? 'success' : 'transcribe_only',
          stage: '处理完成',
          progress: 1,
          outputDir: directory.path,
          completedAt: subtitles.first.lastModifiedSync().toIso8601String(),
          format: bilingual ? '双语 SRT' : '日语 SRT',
        ),
      );
    }
    return history;
  }

  File get _preferencesFile => File(
    _joinPath(_projectRoot.path, '.cache/flutter_preferences.json'),
  );

  File get _historyFile =>
      File(_joinPath(_projectRoot.path, '.cache/flutter_history.json'));

  Future<void> _saveHistory() async {
    final file = _historyFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _history.map((task) => task.toJson()).toList(),
      ),
      flush: true,
    );
  }

  @override
  void dispose() {
    unawaited(_workerSubscription?.cancel());
    final worker = _worker;
    if (worker != null) {
      unawaited(worker.close());
    }
    super.dispose();
  }
}

String _extension(String path) {
  final name = _basename(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

Directory _findProjectRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 10; depth++) {
    if (File(_joinPath(directory.path, 'asmr_worker.py')).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return Directory.current;
}

String _joinPath(String parent, String child) =>
    '$parent${Platform.pathSeparator}${child.replaceAll('/', Platform.pathSeparator)}';

String _stageLabel(String stage) => switch (stage) {
  'audio' => '音频预处理',
  'vad' => 'ASMR 语音检测',
  'asr' => '日语语音转写',
  'translate' => '字幕翻译',
  'quality' => '质量检查',
  _ => stage.isEmpty ? '等待开始' : stage,
};
