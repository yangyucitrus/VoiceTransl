import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/worker_client.dart';

Directory? _findRepositoryRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 10; depth++) {
    if (File(
      '${directory.path}${Platform.pathSeparator}asmr_worker.py',
    ).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return null;
}

String? _integrationSkipReason() {
  final root = _findRepositoryRoot();
  if (root == null) {
    return 'VoiceTransl repository root is unavailable';
  }
  if (!File(
    '${root.path}${Platform.pathSeparator}.venv${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe',
  ).existsSync()) {
    return 'Project virtualenv is unavailable';
  }
  final sample = File(
    '${root.path}${Platform.pathSeparator}files${Platform.pathSeparator}03.mp3',
  );
  final cachedTranscript = File(
    '${root.path}${Platform.pathSeparator}files${Platform.pathSeparator}03.voicetransl${Platform.pathSeparator}cache${Platform.pathSeparator}03.ja.json',
  );
  if (!sample.existsSync() || !cachedTranscript.existsSync()) {
    return 'Cached local integration sample is unavailable';
  }
  return null;
}

void main() {
  test(
    'Flutter client completes a cached Python transcription request',
    () async {
      final root = _findRepositoryRoot()!;
      final sample = File(
        '${root.path}${Platform.pathSeparator}files${Platform.pathSeparator}03.mp3',
      );
      final client = VoiceTranslWorkerClient();
      addTearDown(client.close);

      final ready = client.messages
          .firstWhere((message) => message['type'] == 'ready')
          .timeout(const Duration(seconds: 60));
      await client.start();
      expect((await ready)['protocol'], 1);

      final completed = client.messages
          .firstWhere((message) => message['type'] == 'completed')
          .timeout(const Duration(seconds: 30));
      await client.run(
        inputs: [sample.path],
        options: const {
          'transcribe_only': true,
          'reuse_cache': true,
          'skip_api_preflight': true,
          'limit_segments': 1,
        },
      );
      final message = await completed;
      final results = message['results'] as List<dynamic>;
      final result = Map<String, dynamic>.from(results.single as Map);

      expect(message['cancelled'], isFalse);
      expect(result['status'], 'transcribe_only');
      expect(Directory(result['output_dir'] as String).existsSync(), isTrue);
    },
    skip: _integrationSkipReason() ?? false,
  );
}
