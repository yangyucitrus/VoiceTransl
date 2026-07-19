import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicetransl_flutter/main.dart';

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
}
