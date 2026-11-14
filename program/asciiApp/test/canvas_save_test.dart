import 'dart:convert';
import 'dart:io';

import 'package:ascii_canvas/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets(
      'tap overwrites active draft; long press saves a separate copy; opening binds original',
      (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('ascii-save-'));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory!.path);
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory!.delete(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AsciiCanvasApp());
    await tester.pumpAndSettle();
    final folder = Directory('${directory!.path}/Canvases');
    List<File> files() => folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.asciigarden'))
        .toList();
    Future<void> finishIO() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
      }
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Save canvas'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Canvas name'), 'First');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await finishIO();
    expect(files(), hasLength(1));
    final original = files().single;
    final initial = original.readAsStringSync();
    final surface = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is AsciiPrePainter);
    await tester.tapAt(tester.getCenter(surface));
    await tester.pump();
    await tester.tap(find.byTooltip('Save canvas'));
    await finishIO();
    expect(find.text('Canvas name'), findsNothing);
    expect(files(), hasLength(1));
    expect(original.readAsStringSync(), isNot(initial));
    final firstSaved = original.readAsStringSync();
    await tester.longPress(find.byTooltip('Save canvas'));
    await tester.pumpAndSettle();
    expect(find.text('Save canvas as'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Canvas name'), 'Second');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await finishIO();
    expect(files(), hasLength(2));
    expect(original.readAsStringSync(), firstSaved);
    final copy = files().singleWhere((f) => f.path != original.path);
    final copyBefore = copy.readAsStringSync();
    await tester.tap(find.byTooltip('Open saved canvases'));
    await finishIO();
    await tester.tap(find.text('First'));
    await finishIO();
    await tester.tap(find.byTooltip('Save canvas'));
    await finishIO();
    expect(files(), hasLength(2));
    expect(jsonDecode(original.readAsStringSync())['name'], 'First');
    expect(copy.readAsStringSync(), copyBefore);
    expect(tester.takeException(), isNull);
  });
}
