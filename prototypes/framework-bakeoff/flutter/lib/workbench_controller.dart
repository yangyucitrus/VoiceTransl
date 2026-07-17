import 'dart:async';
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

  bool workerReady = false;
  bool running = false;
  String statusText = '正在连接 Python 后端';
  String lastError = '';
  String transcriptPreview = '';
  String transcriptSource = '';
  List<TaskSnapshot> tasks = const [];
  final List<String> logs = [];

  bool get canStart => workerReady && tasks.isNotEmpty && !running;

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

  List<TaskSnapshot> get completedTasks =>
      tasks.where((task) => task.hasOutput).toList(growable: false);

  String get projectRootPath => _projectRoot.path;

  double get overallProgress {
    if (tasks.isEmpty) {
      return 0;
    }
    return tasks.fold<double>(0, (total, task) => total + task.progress) /
        tasks.length;
  }

  Future<void> initialize() async {
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

  Future<void> reconnectWorker() async {
    if (_worker == null || running) {
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
    statusText = '正在提交转写任务';
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
        options: const {
          'transcribe_only': true,
          'reuse_cache': true,
          'skip_api_preflight': true,
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

  Future<void> loadTranscript([TaskSnapshot? task]) async {
    final completed = completedTasks;
    final target = task ?? (completed.isEmpty ? null : completed.last);
    if (target == null || target.outputDir.isEmpty) {
      transcriptPreview = '';
      transcriptSource = '';
      notifyListeners();
      return;
    }
    final dot = target.name.lastIndexOf('.');
    final stem = dot > 0 ? target.name.substring(0, dot) : target.name;
    final transcript = File(_joinPath(target.outputDir, '$stem.ja.srt'));
    if (!transcript.existsSync()) {
      transcriptPreview = '';
      transcriptSource = transcript.path;
      lastError = '找不到日语字幕：${transcript.path}';
      statusText = '转写稿尚未生成';
      notifyListeners();
      return;
    }
    transcriptPreview = await transcript.readAsString();
    transcriptSource = transcript.path;
    lastError = '';
    statusText = '已加载 ${target.name} 的转写稿';
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
            completedAt: '刚刚',
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
            completedAt: '刚刚',
          ),
        );
      }
    }
    final cancelled = message['cancelled'] == true;
    running = false;
    _activeRequestId = null;
    _requestTaskIndices = const [];
    statusText = cancelled ? '任务已取消' : '本批任务处理完成';
    if (!cancelled && completedTasks.isNotEmpty) {
      unawaited(loadTranscript(completedTasks.last));
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
