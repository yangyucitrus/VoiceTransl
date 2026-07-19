import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class WorkerTransport {
  Stream<Map<String, dynamic>> get messages;

  Future<void> start();

  Future<String> run({
    required List<String> inputs,
    Map<String, dynamic> options = const {},
  });

  Future<void> cancel([String? requestId]);

  Future<Map<String, dynamic>> getConfiguration();

  Future<Map<String, dynamic>> saveConfiguration({
    String? transcriptionIntensity,
    String? translationEndpoint,
    String? translationModel,
    String? apiKey,
  });

  Future<void> close();
}

class WorkerLaunchSpec {
  const WorkerLaunchSpec({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  static WorkerLaunchSpec discover({
    Directory? startDirectory,
    Map<String, String>? environment,
    String? processExecutable,
  }) {
    final env = environment ?? Platform.environment;
    final override = env['VOICETRANSL_WORKER'];
    if (override != null && override.trim().isNotEmpty) {
      return _fromWorkerPath(File(override.trim()), env);
    }

    final executableDirectory = File(
      processExecutable ?? Platform.resolvedExecutable,
    ).parent;
    final packagedWorker = File(
      _join([executableDirectory.path, 'backend', 'voicetransl-worker.exe']),
    );
    if (packagedWorker.existsSync()) {
      return WorkerLaunchSpec(
        executable: packagedWorker.path,
        arguments: const [],
        workingDirectory: executableDirectory.path,
      );
    }

    var directory = startDirectory ?? Directory.current;
    for (var depth = 0; depth < 10; depth++) {
      final worker = File(_join([directory.path, 'asmr_worker.py']));
      if (worker.existsSync()) {
        return _fromWorkerPath(worker, env);
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
    throw StateError(
      '找不到 VoiceTransl Python worker。请设置 VOICETRANSL_WORKER，'
      '或从项目目录启动应用。',
    );
  }

  static WorkerLaunchSpec _fromWorkerPath(
    File worker,
    Map<String, String> environment,
  ) {
    if (!worker.existsSync()) {
      throw StateError('Worker 不存在：${worker.path}');
    }
    if (worker.path.toLowerCase().endsWith('.exe')) {
      return WorkerLaunchSpec(
        executable: worker.path,
        arguments: const [],
        workingDirectory: worker.parent.path,
      );
    }

    final root = worker.parent;
    final configuredPython = environment['VOICETRANSL_PYTHON'];
    final venvPython = File(
      _join([root.path, '.venv', 'Scripts', 'python.exe']),
    );
    final python =
        configuredPython != null && configuredPython.trim().isNotEmpty
        ? configuredPython.trim()
        : venvPython.existsSync()
        ? venvPython.path
        : 'python';
    return WorkerLaunchSpec(
      executable: python,
      arguments: ['-u', worker.path],
      workingDirectory: root.path,
    );
  }

  static String _join(List<String> parts) => parts.join(Platform.pathSeparator);
}

class VoiceTranslWorkerClient implements WorkerTransport {
  VoiceTranslWorkerClient({WorkerLaunchSpec? launchSpec})
    : _launchSpec = launchSpec;

  final WorkerLaunchSpec? _launchSpec;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _closing = false;
  int _requestCounter = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<void> start() async {
    if (_process != null) {
      return;
    }
    final spec = _launchSpec ?? WorkerLaunchSpec.discover();
    final process = await Process.start(
      spec.executable,
      spec.arguments,
      workingDirectory: spec.workingDirectory,
      environment: const {'PYTHONUTF8': '1', 'PYTHONUNBUFFERED': '1'},
      includeParentEnvironment: true,
      runInShell: false,
    );
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isNotEmpty && !_messages.isClosed) {
            _messages.add({'type': 'log', 'message': line});
          }
        });
    unawaited(
      process.exitCode.then((exitCode) {
        _process = null;
        for (final pending in _pendingRequests.values) {
          if (!pending.isCompleted) {
            pending.completeError(
              StateError('Python worker 已退出（代码 $exitCode）'),
            );
          }
        }
        _pendingRequests.clear();
        if (!_closing && !_messages.isClosed) {
          _messages.add({'type': 'worker_exit', 'exit_code': exitCode});
        }
      }),
    );
  }

  @override
  Future<String> run({
    required List<String> inputs,
    Map<String, dynamic> options = const {},
  }) async {
    final requestId = _nextRequestId('run');
    _send({
      'command': 'run',
      'request_id': requestId,
      'inputs': inputs,
      'options': options,
    });
    return requestId;
  }

  @override
  Future<void> cancel([String? requestId]) async {
    _send({'command': 'cancel', 'request_id': requestId});
  }

  @override
  Future<Map<String, dynamic>> getConfiguration() {
    return _request('get_config');
  }

  @override
  Future<Map<String, dynamic>> saveConfiguration({
    String? transcriptionIntensity,
    String? translationEndpoint,
    String? translationModel,
    String? apiKey,
  }) {
    return _request(
      'save_config',
      payload: {
        'config': {
          if (transcriptionIntensity != null)
            'transcription_intensity': transcriptionIntensity,
          if (translationEndpoint != null)
            'translation_endpoint': translationEndpoint,
          if (translationModel != null) 'translation_model': translationModel,
          if (apiKey != null && apiKey.trim().isNotEmpty)
            'api_key': apiKey.trim(),
        },
      },
    );
  }

  Future<void> ping() async {
    _send({
      'command': 'ping',
      'request_id': 'ping-${DateTime.now().microsecondsSinceEpoch}',
    });
  }

  String _nextRequestId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_requestCounter++}';

  Future<Map<String, dynamic>> _request(
    String command, {
    Map<String, dynamic> payload = const {},
  }) {
    final requestId = _nextRequestId(command);
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;
    try {
      _send({'command': command, 'request_id': requestId, ...payload});
    } catch (error, stackTrace) {
      _pendingRequests.remove(requestId);
      Error.throwWithStackTrace(error, stackTrace);
    }
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw TimeoutException('Python worker 配置请求超时');
      },
    );
  }

  void _send(Map<String, dynamic> message) {
    final process = _process;
    if (process == null) {
      throw StateError('Python worker 尚未启动');
    }
    process.stdin.writeln(jsonEncode(message));
  }

  void _handleStdoutLine(String line) {
    if (line.trim().isEmpty || _messages.isClosed) {
      return;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Worker message is not a JSON object');
      }
      final message = Map<String, dynamic>.from(decoded);
      final requestId = message['request_id']?.toString();
      final pending = requestId == null
          ? null
          : _pendingRequests.remove(requestId);
      if (pending != null) {
        final type = message['type']?.toString();
        if (type == 'rejected' || type == 'error' || type == 'protocol_error') {
          pending.completeError(
            StateError(message['message']?.toString() ?? '配置请求失败'),
          );
        } else {
          pending.complete(message);
        }
        return;
      }
      _messages.add(message);
    } catch (error) {
      _messages.add({
        'type': 'protocol_error',
        'message': '无法解析 worker 输出：$error',
        'line': line,
      });
    }
  }

  @override
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    for (final pending in _pendingRequests.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Python worker 已关闭'));
      }
    }
    _pendingRequests.clear();
    final process = _process;
    if (process != null) {
      try {
        _send({'command': 'shutdown'});
        await process.stdin.flush();
        await process.stdin.close();
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on Object {
        process.kill();
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _messages.close();
  }
}
