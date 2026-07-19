import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/main.dart';
import 'package:voicetransl_flutter/workbench_controller.dart';
import 'package:voicetransl_flutter/worker_client.dart';

class UiFakeWorker implements WorkerTransport {
  final messagesController =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  String? savedEndpoint;
  String? savedModel;
  String? savedApiKey;
  String intensity = 'medium';

  @override
  Stream<Map<String, dynamic>> get messages => messagesController.stream;

  @override
  Future<void> start() async {
    messagesController.add({'type': 'ready', 'protocol': 1});
  }

  Map<String, dynamic> get config => {
    'transcription_intensity': intensity,
    'device_preset': 'gpu_quality',
    'translation_endpoint': savedEndpoint ?? 'https://api.deepseek.com',
    'translation_model': savedModel ?? 'deepseek-v4-flash',
    'api_key_configured': savedApiKey != null,
  };

  @override
  Future<Map<String, dynamic>> getConfiguration() async => {
    'type': 'config',
    'config': config,
  };

  @override
  Future<Map<String, dynamic>> saveConfiguration({
    String? transcriptionIntensity,
    String? translationEndpoint,
    String? translationModel,
    String? apiKey,
  }) async {
    intensity = transcriptionIntensity ?? intensity;
    savedEndpoint = translationEndpoint ?? savedEndpoint;
    savedModel = translationModel ?? savedModel;
    savedApiKey = apiKey ?? savedApiKey;
    return {'type': 'config_saved', 'config': config};
  }

  @override
  Future<Map<String, dynamic>> inspectStorage(
    List<Map<String, String>> items,
  ) async => {
    'type': 'storage',
    'items': [
      for (final item in items)
        {
          ...item,
          'exists': true,
          'final_bytes': 100,
          'cache_bytes': 1000,
          'reclaimable_bytes': 900,
          'cache_state': 'tracked',
        },
    ],
  };

  @override
  Future<Map<String, dynamic>> cleanupOutputs({
    required List<Map<String, String>> items,
    required String mode,
  }) async => {
    'type': 'outputs_cleaned',
    'mode': mode,
    'items': [
      for (final item in items)
        {
          ...item,
          'exists': mode != 'delete_result',
          'final_bytes': mode == 'delete_result' ? 0 : 100,
          'cache_bytes': 0,
          'reclaimable_bytes': 0,
          'cache_state': 'none',
          'freed_bytes': 1000,
          'deleted': mode == 'delete_result',
        },
    ],
    'freed_bytes': 1000 * items.length,
    'deleted_count': mode == 'delete_result' ? items.length : 0,
  };

  @override
  Future<Map<String, dynamic>> prepareRetry({
    required Map<String, String> item,
    required String stage,
  }) async => {
    'type': 'retry_prepared',
    'stage': stage,
    ...item,
    'exists': true,
    'final_bytes': 0,
    'cache_bytes': 0,
    'reclaimable_bytes': 0,
    'cache_state': 'none',
  };

  @override
  Future<String> run({
    required List<String> inputs,
    Map<String, dynamic> options = const {},
  }) async => 'unused';

  @override
  Future<void> cancel([String? requestId]) async {}

  @override
  Future<void> close() => messagesController.close();
}

void main() {
  Future<void> pumpWorkbench(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const VoiceTranslApp(demoMode: true));
    await tester.pumpAndSettle();
  }

  testWidgets('every sidebar destination replaces the main page', (
    tester,
  ) async {
    await pumpWorkbench(tester);

    expect(find.byKey(const ValueKey('workbench-page')), findsOneWidget);
    const destinations = {
      1: 'media-library-page',
      2: 'dictionary-page',
      3: 'export-history-page',
      4: 'settings-page',
    };
    for (final destination in destinations.entries) {
      await tester.tap(find.byKey(ValueKey('sidebar-nav-${destination.key}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey(destination.value)),
        findsOneWidget,
        reason: 'destination ${destination.key} should render its own page',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('transcript tab replaces the queue content', (tester) async {
    await pumpWorkbench(tester);

    await tester.tap(find.text('字幕预览'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('transcript-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-page')), findsNothing);
  });

  testWidgets('live log button streams new worker lines while open', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('voicetransl-ui-log-');
    addTearDown(() => root.deleteSync(recursive: true));
    final worker = UiFakeWorker();
    final controller = WorkbenchController(worker: worker, projectRoot: root);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(
      VoiceTranslApp(demoMode: true, controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('live-log-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-log-dialog')), findsOneWidget);

    worker.messagesController.add({
      'type': 'log',
      'message': 'VAD chunk 2/4',
    });
    await tester.pump();

    expect(find.textContaining('VAD chunk 2/4'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-log-list')), findsOneWidget);
  });

  testWidgets('preflight failure leaves processing stages pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-ui-preflight-failure-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final worker = UiFakeWorker();
    final controller = WorkbenchController(worker: worker, projectRoot: root);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    controller.tasks = const [
      TaskSnapshot(
        path: 'scene.wav',
        name: 'scene.wav',
        status: 'failed',
        stage: 'preflight failed',
        stageKey: '',
        error: 'API generation preflight timed out',
      ),
    ];
    controller.lastError = 'API generation preflight timed out';
    await tester.pumpWidget(
      VoiceTranslApp(demoMode: true, controller: controller),
    );
    await tester.pumpAndSettle();

    for (final key in const [
      'activity-audio',
      'activity-asr',
      'activity-translation',
    ]) {
      final line = find.byKey(ValueKey(key));
      expect(line, findsOneWidget);
      expect(
        find.descendant(
          of: line,
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: line,
          matching: find.byIcon(Icons.radio_button_unchecked_rounded),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('view all opens export history', (tester) async {
    await pumpWorkbench(tester);

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('export-history-page')), findsOneWidget);
  });

  testWidgets('more menu routes to settings', (tester) async {
    await pumpWorkbench(tester);

    await tester.tap(find.byTooltip('更多选项'));
    await tester.pumpAndSettle();
    expect(find.text('打开项目目录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-settings-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
  });

  testWidgets('configures transcription intensity and OpenAI translation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('voicetransl-ui-config-');
    addTearDown(() => root.deleteSync(recursive: true));
    final worker = UiFakeWorker();
    final controller = WorkbenchController(
      worker: worker,
      projectRoot: root,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(
      VoiceTranslApp(demoMode: true, controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sidebar-nav-4')));
    await tester.pumpAndSettle();
    expect(find.text('本地转写强度'), findsOneWidget);
    expect(find.text('中'), findsOneWidget);
    expect(controller.workerReady, isTrue);
    expect(controller.configurationBusy, isFalse);

    final highIntensity = find.byKey(
      const ValueKey('transcription-intensity-high'),
    );
    await tester.ensureVisible(highIntensity);
    await tester.pumpAndSettle();
    await tester.tap(highIntensity);
    await tester.pumpAndSettle();
    expect(worker.intensity, 'high');

    await tester.ensureVisible(find.text('配置接口'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置接口'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('translation-config-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-endpoint-field')),
      'http://127.0.0.1:8000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-model-field')),
      'local-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-api-key-field')),
      'secret-value',
    );
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(worker.savedEndpoint, 'http://127.0.0.1:8000');
    expect(worker.savedModel, 'local-model');
    expect(worker.savedApiKey, 'secret-value');
    expect(
      find.byKey(const ValueKey('translation-config-dialog')),
      findsNothing,
    );
  });

  testWidgets('result library exposes storage and guarded cleanup actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final separator = Platform.pathSeparator;
    final root = Directory.systemTemp.createTempSync(
      'voicetransl-ui-results-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final files = Directory([root.path, 'files'].join(separator))..createSync();
    File([files.path, 'scene.wav'].join(separator)).writeAsStringSync('audio');
    final output = Directory(
      [files.path, 'scene.voicetransl'].join(separator),
    )..createSync();
    File(
      [output.path, 'scene.ja.srt'].join(separator),
    ).writeAsStringSync('subtitle');
    final worker = UiFakeWorker();
    final controller = WorkbenchController(worker: worker, projectRoot: root);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpWidget(
      VoiceTranslApp(demoMode: true, controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sidebar-nav-3')));
    await tester.pumpAndSettle();

    expect(find.textContaining('成品 100 B'), findsOneWidget);
    expect(find.textContaining('可清理 900 B'), findsOneWidget);
    expect(find.text('可清 900 B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('result-manage-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('result-safe-clean-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('confirm-safe_cache')),
      findsOneWidget,
    );
    expect(find.textContaining('源音频'), findsNothing);
    expect(find.textContaining('保留所有 SRT'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多结果操作'));
    await tester.pumpAndSettle();
    expect(find.text('仅重新翻译'), findsOneWidget);
    expect(find.text('重新转写'), findsOneWidget);
    expect(find.text('删除生成结果'), findsOneWidget);
    await tester.tap(find.text('删除生成结果'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('confirm-delete_result')),
      findsOneWidget,
    );
    expect(find.textContaining('源音频不会被删除'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
