import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/main.dart';

Future<void> _loadFont(String family, String fontPath) async {
  final file = File(fontPath);
  if (!file.existsSync()) {
    return;
  }

  final bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc');
    await _loadFont(
      'MaterialIcons',
      r'E:\asmr\VoiceTransl\.tooling\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    );
  });

  testWidgets('renders the bright desktop workbench', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const VoiceTranslApp(demoMode: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byKey(const ValueKey('app-canvas')),
      matchesGoldenFile('goldens/flutter-light-workbench.png'),
    );
  });

  testWidgets('fits a compact desktop without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const VoiceTranslApp(demoMode: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('任务队列'), findsOneWidget);
    expect(find.text('RJ01423376_track01.wav'), findsOneWidget);
    expect(find.text('声纹助手'), findsNothing);
  });
}
