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
      '素材库': 'media-library-page',
      '词汇表': 'dictionary-page',
      '导出记录': 'export-history-page',
      '设置': 'settings-page',
    };
    for (final destination in destinations.entries) {
      await tester.tap(find.text(destination.key));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey(destination.value)),
        findsOneWidget,
        reason: '${destination.key} should render its own page',
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

  testWidgets('notifications button opens the activity dialog', (tester) async {
    await pumpWorkbench(tester);

    await tester.tap(find.byTooltip('通知'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('activity-dialog')), findsOneWidget);
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
    await tester.tap(find.text('设置').last);
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
    await tester.pumpWidget(VoiceTranslApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('本地转写强度'), findsOneWidget);
    expect(find.text('中'), findsOneWidget);

    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(worker.intensity, 'high');

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
}
