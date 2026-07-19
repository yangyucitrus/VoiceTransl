import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/workbench_controller.dart';
import 'package:voicetransl_flutter/worker_client.dart';

class FakeWorker implements WorkerTransport {
  final controller = StreamController<Map<String, dynamic>>.broadcast(
    sync: true,
  );
  List<String> lastInputs = const [];
  Map<String, dynamic> lastOptions = const {};
  String? cancelledRequest;
  String? savedApiKey;
  Map<String, dynamic> runtimeConfig = {
    'transcription_intensity': 'medium',
    'device_preset': 'gpu_quality',
    'translation_endpoint': 'https://api.deepseek.com',
    'translation_model': 'deepseek-v4-flash',
    'api_key_configured': false,
  };
  int startCount = 0;

  @override
  Stream<Map<String, dynamic>> get messages => controller.stream;

  @override
  Future<void> start() async {
    startCount += 1;
    if (startCount == 1) {
      controller.add({'type': 'ready', 'protocol': 1});
    }
  }

  @override
  Future<String> run({
    required List<String> inputs,
    Map<String, dynamic> options = const {},
  }) async {
    lastInputs = inputs;
    lastOptions = options;
    return 'run-1';
  }

  @override
  Future<void> cancel([String? requestId]) async {
    cancelledRequest = requestId;
  }

  @override
  Future<Map<String, dynamic>> getConfiguration() async {
    return {'type': 'config', 'config': Map.of(runtimeConfig)};
  }

  @override
  Future<Map<String, dynamic>> saveConfiguration({
    String? transcriptionIntensity,
    String? translationEndpoint,
    String? translationModel,
    String? apiKey,
  }) async {
    if (transcriptionIntensity != null) {
      runtimeConfig['transcription_intensity'] = transcriptionIntensity;
    }
    if (translationEndpoint != null) {
      runtimeConfig['translation_endpoint'] = translationEndpoint;
    }
    if (translationModel != null) {
      runtimeConfig['translation_model'] = translationModel;
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      savedApiKey = apiKey;
      runtimeConfig['api_key_configured'] = true;
    }
    return {'type': 'config_saved', 'config': Map.of(runtimeConfig)};
  }

  @override
  Future<void> close() async {
    await controller.close();
  }

  void emit(Map<String, dynamic> message) => controller.add(message);
}

class FakePicker implements MediaPicker {
  FakePicker(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> pickFiles() async => paths;

  @override
  Future<List<String>> pickDirectory() async => paths;
}

class FakeWorkspaceLauncher implements WorkspaceLauncher {
  String? openedDirectory;
  String? openedFile;

  @override
  Future<void> openDirectory(String path) async {
    openedDirectory = path;
  }

  @override
  Future<void> openFile(String path) async {
    openedFile = path;
  }
}

void main() {
  test('checking an active worker preserves the connected state', () async {
    final worker = FakeWorker();
    final controller = WorkbenchController(
      worker: worker,
      mediaPicker: FakePicker(const []),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.reconnectWorker();

    expect(controller.workerReady, isTrue);
    expect(controller.statusText, 'Python 后端连接正常');
    expect(worker.startCount, 1);
  });

  test('runs a selected file and applies worker progress', () async {
    final worker = FakeWorker();
    final controller = WorkbenchController(
      worker: worker,
      mediaPicker: FakePicker([r'C:\audio\scene.wav']),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.pickFiles();
    await controller.startTasks();

    expect(controller.workerReady, isTrue);
    expect(worker.lastInputs, [r'C:\audio\scene.wav']);
    expect(worker.lastOptions['transcribe_only'], isFalse);
    expect(worker.lastOptions['reuse_cache'], isTrue);
    expect(worker.lastOptions['skip_api_preflight'], isFalse);

    worker.emit({
      'type': 'event',
      'request_id': 'run-1',
      'event': {
        'type': 'stage_progress',
        'file_index': 0,
        'stage': 'asr',
        'stage_index': 3,
        'stage_count': 5,
        'progress': 0.5,
      },
    });

    expect(controller.activeTask?.progress, closeTo(0.5, 0.001));

    worker.emit({
      'type': 'completed',
      'request_id': 'run-1',
      'cancelled': false,
      'results': [
        {
          'input_path': r'C:\audio\scene.wav',
          'name': 'scene.wav',
          'status': 'transcribe_only',
          'output_dir': r'C:\audio\scene.voicetransl',
          'warnings': 0,
          'error': null,
        },
      ],
    });

    expect(controller.running, isFalse);
    expect(controller.tasks.single.status, 'transcribe_only');
    expect(controller.tasks.single.outputDir, r'C:\audio\scene.voicetransl');
    expect(controller.canStart, isFalse);
  });

  test('forwards cancellation for the active request', () async {
    final worker = FakeWorker();
    final controller = WorkbenchController(
      worker: worker,
      mediaPicker: FakePicker([r'C:\audio\scene.wav']),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.pickFiles();
    await controller.startTasks();
    await controller.cancel();

    expect(worker.cancelledRequest, 'run-1');
    expect(controller.statusText, '正在等待安全停止点');
  });

  test('discovers the development worker and project virtualenv', () {
    final separator = Platform.pathSeparator;
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-worker-test-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final nested = Directory(
      [root.path, 'prototypes', 'framework-bakeoff', 'flutter'].join(separator),
    )..createSync(recursive: true);
    File([root.path, 'asmr_worker.py'].join(separator)).createSync();
    File(
      [root.path, '.venv', 'Scripts', 'python.exe'].join(separator),
    ).createSync(recursive: true);

    final spec = WorkerLaunchSpec.discover(
      startDirectory: nested,
      environment: const {},
      processExecutable: r'C:\fake\flutter_tester.exe',
    );

    expect(spec.executable, endsWith(r'.venv\Scripts\python.exe'));
    expect(spec.arguments.last, endsWith('asmr_worker.py'));
  });

  test('manages queued media and launches workspace paths', () async {
    final separator = Platform.pathSeparator;
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-actions-test-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final settings = File([root.path, 'settings.yaml'].join(separator))
      ..writeAsStringSync('pipeline: {}');
    final models = Directory([root.path, 'models'].join(separator))
      ..createSync();
    final launcher = FakeWorkspaceLauncher();
    final controller = WorkbenchController(
      worker: FakeWorker(),
      mediaPicker: FakePicker([r'C:\audio\scene.wav']),
      workspaceLauncher: launcher,
      projectRoot: root,
    );
    addTearDown(controller.dispose);

    await controller.pickFiles();
    expect(controller.tasks, hasLength(1));
    controller.removeTask(controller.tasks.single);
    expect(controller.tasks, isEmpty);

    await controller.openWorkspaceFile('settings.yaml');
    await controller.openWorkspaceDirectory('models');
    await controller.openProjectDirectory();

    expect(launcher.openedFile, settings.path);
    expect(launcher.openedDirectory, root.path);
    expect(models.existsSync(), isTrue);
  });

  test('persists run preferences and forwards transcribe-only mode', () async {
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-preferences-test-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final firstWorker = FakeWorker();
    final first = WorkbenchController(
      worker: firstWorker,
      mediaPicker: FakePicker([r'C:\audio\scene.wav']),
      projectRoot: root,
    );
    addTearDown(first.dispose);

    await first.setTranslationEnabled(false);
    await first.setReuseCache(false);
    await first.setApiPreflight(false);
    await first.initialize();
    await first.pickFiles();
    await first.startTasks();

    expect(firstWorker.lastOptions['transcribe_only'], isTrue);
    expect(firstWorker.lastOptions['reuse_cache'], isFalse);
    expect(firstWorker.lastOptions['skip_api_preflight'], isTrue);

    final second = WorkbenchController(
      worker: FakeWorker(),
      mediaPicker: FakePicker(const []),
      projectRoot: root,
    );
    addTearDown(second.dispose);
    await second.initialize();

    expect(second.translationEnabled, isFalse);
    expect(second.reuseCache, isFalse);
    expect(second.apiPreflight, isFalse);
  });

  test('loads and saves transcription and translation configuration', () async {
    final worker = FakeWorker();
    final controller = WorkbenchController(
      worker: worker,
      mediaPicker: FakePicker(const []),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.transcriptionIntensity, 'medium');
    expect(controller.translationModel, 'deepseek-v4-flash');
    expect(controller.apiKeyConfigured, isFalse);

    await controller.setTranscriptionIntensity('high');
    await controller.saveTranslationConfiguration(
      endpoint: 'http://127.0.0.1:8000',
      model: 'local-translator',
      apiKey: 'local-secret',
    );

    expect(controller.transcriptionIntensity, 'high');
    expect(controller.translationEndpoint, 'http://127.0.0.1:8000');
    expect(controller.translationModel, 'local-translator');
    expect(controller.apiKeyConfigured, isTrue);
    expect(worker.savedApiKey, 'local-secret');
  });

  test('edits allowlisted workspace text without an external editor', () async {
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-text-editor-test-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final settings = File('${root.path}${Platform.pathSeparator}settings.yaml')
      ..writeAsStringSync('pipeline:\n  transcribe_only: false\n');
    final controller = WorkbenchController(
      worker: FakeWorker(),
      mediaPicker: FakePicker(const []),
      projectRoot: root,
    );
    addTearDown(controller.dispose);

    expect(await controller.readWorkspaceText('settings.yaml'), contains('pipeline'));
    await controller.saveWorkspaceText('settings.yaml', 'pipeline: {}\n');

    expect(settings.readAsStringSync(), 'pipeline: {}\n');
    expect(controller.readWorkspaceText('../.env'), throwsArgumentError);
  });

  test('discovers output history and restores a bilingual transcript', () async {
    final separator = Platform.pathSeparator;
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-history-test-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final files = Directory([root.path, 'files'].join(separator))..createSync();
    File([files.path, 'scene.wav'].join(separator)).writeAsStringSync('audio');
    final output = Directory(
      [files.path, 'scene.voicetransl'].join(separator),
    )..createSync();
    File(
      [output.path, 'scene.combine.srt'].join(separator),
    ).writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nこんにちは\n你好\n');

    final controller = WorkbenchController(
      worker: FakeWorker(),
      mediaPicker: FakePicker(const []),
      projectRoot: root,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.loadTranscript();

    expect(controller.completedTasks, hasLength(1));
    expect(controller.completedTasks.single.format, '双语 SRT');
    expect(controller.transcriptSource, endsWith('scene.combine.srt'));
    expect(controller.transcriptPreview, contains('你好'));
    expect(
      File(
        [root.path, '.cache', 'flutter_history.json'].join(separator),
      ).existsSync(),
      isTrue,
    );
  });
}
