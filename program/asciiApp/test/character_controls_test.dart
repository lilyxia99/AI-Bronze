import 'dart:convert';

import 'package:ascii_canvas/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> openApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const AsciiCanvasApp());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('multi-select deletes only selected characters and supports undo',
      (tester) async {
    await openApp(tester);
    await tester.tap(find.byTooltip('Select multiple characters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@'));
    await tester.pump();
    await tester.tap(find.text('#'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete 2 selected characters'));
    await tester.pumpAndSettle();
    expect(find.text('@'), findsNothing);
    expect(find.text('#'), findsNothing);
    expect(find.text('%'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.text('@'), findsOneWidget);
    expect(find.text('#'), findsOneWidget);
  });

  testWidgets(
      'delete mode removes a tapped character and permits an empty palette',
      (tester) async {
    await openApp(tester);
    await tester
        .tap(find.byTooltip('Delete mode: tap a character to remove it'));
    await tester.pump();
    await tester.tap(find.text('@'));
    await tester.pumpAndSettle();
    expect(find.text('@'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.tap(find.byTooltip('Select multiple characters'));
    await tester.pump();
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete 12 selected characters'));
    await tester.pumpAndSettle();
    final saved = jsonDecode((await SharedPreferencesAsync()
        .getString('ascii_garden_palettes_v1'))!) as Map<String, dynamic>;
    expect(saved['Ink'], isEmpty);
    await tester.pumpWidget(AsciiCanvasApp(key: UniqueKey()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '?');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final restored = jsonDecode((await SharedPreferencesAsync()
        .getString('ascii_garden_palettes_v1'))!) as Map<String, dynamic>;
    expect(restored['Ink'], ['?']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press and drag reorders and persists characters',
      (tester) async {
    await openApp(tester);
    final start = tester.getCenter(find.text('@'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(start + const Offset(110, 0));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    final saved = jsonDecode((await SharedPreferencesAsync()
        .getString('ascii_garden_palettes_v1'))!) as Map<String, dynamic>;
    final characters = saved['Ink'] as List<dynamic>;
    expect(characters.indexOf('@'), greaterThan(characters.indexOf('#')));
    expect(characters.length, 13);
  });

  testWidgets('center fits and centers an oversized canvas after panning',
      (tester) async {
    await openApp(tester);
    await tester.tap(find.text('36 × 25'));
    await tester.pumpAndSettle();
    final inputs = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(inputs.at(0), '72');
    await tester.enterText(inputs.at(1), '50');
    await tester.tap(find.text('Resize'));
    await tester.pumpAndSettle();
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()
      ..setTranslationRaw(-300, -250, 0);
    await tester.pump();
    await tester.tap(find.byTooltip('Center and fit canvas'));
    await tester.pumpAndSettle();
    final matrix = viewer.transformationController!.value;
    final stage = viewer.child as SizedBox;
    final viewport = tester.getSize(find.byType(InteractiveViewer));
    final scale = matrix.storage[0];
    expect(matrix.storage[12] + stage.width! * scale / 2,
        closeTo(viewport.width / 2, 0.01));
    expect(matrix.storage[13] + stage.height! * scale / 2,
        closeTo(viewport.height / 2, 0.01));
    expect(scale, lessThan(1));
  });
}
