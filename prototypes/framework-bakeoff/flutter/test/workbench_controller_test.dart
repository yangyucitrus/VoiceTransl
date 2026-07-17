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

  @override
  Stream<Map<String, dynamic>> get messages => controller.stream;

  @override
  Future<void> start() async {
    controller.add({'type': 'ready', 'protocol': 1});
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
    expect(worker.lastOptions['transcribe_only'], isTrue);

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
}
