import 'dart:ui' as ui;

import 'package:ascii_canvas/main.dart';
import 'package:ascii_canvas/preformatted_ascii.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<Uint8List> rasterize(Size size, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = Uint8List.fromList(bytes.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('AsciiCode')
      ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'));
    await loader.load();
  });

  test(
      'ASCII art matches one unwrapped preformatted text block pixel for pixel',
      () async {
    final lines = [' /\\ /\\', '( o.o )', '  |__|', '', '    @'];
    final grid = lines.map((line) => line.padRight(20).split('')).toList();
    final layout = PreformattedAsciiLayout(grid);
    final text = lines.map((line) => line.padRight(20)).join('\n');
    final reference = TextPainter(
      text: TextSpan(text: text, style: PreformattedAsciiLayout.textStyle),
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.longestLine,
      textScaler: TextScaler.noScaling,
    )..layout();
    expect(layout.text, text);
    expect(layout.painter.computeLineMetrics().length, lines.length);
    final actual = await rasterize(layout.size, layout.paint);
    final expected = await rasterize(
        layout.size, (canvas) => reference.paint(canvas, Offset.zero));
    expect(actual, orderedEquals(expected));
    for (final character in ['i', 'W', '/', r'\', '_', '&', ' ']) {
      final glyph = TextPainter(
        text:
            TextSpan(text: character, style: PreformattedAsciiLayout.textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(glyph.width, closeTo(layout.characterAdvance, 0.001));
      glyph.dispose();
    }
    reference.dispose();
    layout.dispose();
  });

  test('touch positions follow actual glyph advances, including blank cells',
      () {
    final grid =
        ['  /_& ', '      ', ' X    '].map((line) => line.split('')).toList();
    final layout = PreformattedAsciiLayout(grid);
    for (var row = 0; row < grid.length; row++) {
      for (var column = 0; column < grid[row].length; column++) {
        final offset = row * 7 + column;
        final boxes = layout.painter.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        );
        final bounds = boxes.single.toRect();
        for (final fraction in [0.15, 0.85]) {
          final hit = layout.cellAt(
              Offset(bounds.left + bounds.width * fraction, bounds.center.dy));
          expect(hit?.x, column);
          expect(hit?.y, row);
        }
      }
    }
    expect(layout.cellAt(const Offset(-1, -1)), isNull);
    layout.dispose();
  });

  test('Unicode fallback keeps native width without corrupting cell indices',
      () {
    final layout = PreformattedAsciiLayout([
      ['😀', 'A', ' '],
      [' ', 'W', '?'],
    ]);
    for (final entry in [(2, 1, 0), (6, 1, 1)]) {
      final bounds = layout.painter
          .getBoxesForSelection(
              TextSelection(baseOffset: entry.$1, extentOffset: entry.$1 + 1))
          .single
          .toRect();
      final cell = layout.cellAt(bounds.center);
      expect(cell?.x, entry.$2);
      expect(cell?.y, entry.$3);
    }
    layout.dispose();
  });

  testWidgets('drawing and Copy art preserve every blank cell and newline',
      (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const AsciiCanvasApp());
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is AsciiPrePainter);
    final layout =
        (tester.widget<CustomPaint>(surface).painter! as AsciiPrePainter)
            .layout;
    const index = 3 * 37 + 4;
    final bounds = layout.painter
        .getBoxesForSelection(
            const TextSelection(baseOffset: index, extentOffset: index + 1))
        .single
        .toRect();
    await tester.tapAt(tester.getTopLeft(surface) + bounds.center);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy art'));
    await tester.pumpAndSettle();
    final lines = copied!.split('\n');
    expect(lines.length, 25);
    expect(lines.every((line) => line.length == 36), isTrue);
    expect(lines[3][4], '@');
    expect(lines[3].endsWith(' ' * 31), isTrue);
  });
}
