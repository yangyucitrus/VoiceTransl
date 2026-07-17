import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the transparent assistant asset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: const Color(0xFFFFF3F7),
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('mascot-canvas'),
              child: Image.asset(
                'assets/assistant.png',
                width: 240,
                height: 300,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/assistant.png'),
        tester.element(find.byKey(const ValueKey('mascot-canvas'))),
      );
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byKey(const ValueKey('mascot-canvas')),
      matchesGoldenFile('goldens/flutter-mascot-asset.png'),
    );
  });
}
