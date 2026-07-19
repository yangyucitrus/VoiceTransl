import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/main.dart';

void main() {
  testWidgets('renders the bright desktop workbench', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const VoiceTranslApp(demoMode: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('app-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-mark')), findsOneWidget);
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
