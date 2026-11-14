import 'package:ascii_canvas/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('select, preview, move and undo art on a narrow phone',
      (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final loader = FontLoader('AsciiCode')
      ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'));
    await loader.load();
    await tester.pumpWidget(const AsciiCanvasApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Center and fit canvas'));
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is AsciiPrePainter);
    AsciiPrePainter painter() =>
        tester.widget<CustomPaint>(surface).painter! as AsciiPrePainter;
    Offset cell(int col, int row) {
      final layout = painter().layout;
      final box = layout.painter
          .getBoxesForSelection(TextSelection(
              baseOffset: row * 37 + col, extentOffset: row * 37 + col + 1))
          .single
          .toRect();
      final render = tester.renderObject<RenderBox>(surface);
      return render.localToGlobal(box.center);
    }

    await tester.tapAt(cell(3, 3));
    await tester.pump();
    expect(painter().layout.text.split('\n')[3][3], '@');
    await tester.tap(find.byTooltip('Select and move art'));
    await tester.pump();
    var drag = await tester.startGesture(cell(2, 2));
    await drag.moveTo(cell(6, 5));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(painter().selection!.left, 2);
    expect(painter().selection!.right, 6);
    final start = cell(3, 3);
    final end = cell(8, 7);
    drag = await tester.startGesture(start);
    await drag.moveTo(end);
    await tester.pump();
    expect(painter().layout.text.split('\n')[7][8], '@');
    await drag.up();
    await tester.pump();
    expect(painter().layout.text.split('\n')[3][3], ' ');
    expect(painter().layout.text.split('\n')[7][8], '@');
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(painter().layout.text.split('\n')[3][3], '@');
    expect(painter().layout.text.split('\n')[7][8], ' ');
    expect(tester.takeException(), isNull);
  });
}
