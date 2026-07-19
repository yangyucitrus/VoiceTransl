import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/main.dart';

void main() {
  testWidgets('renders the symbolic voice assistant mark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const VoiceTranslApp(demoMode: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('voice-mark')), findsOneWidget);
    expect(find.text('声纹助手'), findsOneWidget);
  });
}
