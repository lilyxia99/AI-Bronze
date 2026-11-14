import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// One unwrapped text block, using the same advances and baselines for display
/// and hit testing. Spaces and newlines are never trimmed or cell-centered.
class PreformattedAsciiLayout {
  PreformattedAsciiLayout(List<List<String>> grid)
      : text = grid.map((row) => row.join()).join('\n'),
        rowCount = grid.length,
        columnCount = grid.isEmpty ? 0 : grid.first.length {
    var offset = 0;
    for (final row in grid) {
      _rowStarts.add(offset);
      final cells = <int>[];
      for (final character in row) {
        cells.add(offset);
        offset += character.length;
      }
      _cellStarts.add(cells);
      offset++; // The newline between rows occupies one UTF-16 code unit.
    }
    painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textWidthBasis: TextWidthBasis.longestLine,
      textScaler: TextScaler.noScaling,
    )..layout();
    final probe = TextPainter(
      text: const TextSpan(text: '0', style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    characterAdvance = probe.width;
    lineAdvance = probe.preferredLineHeight;
    probe.dispose();
    size = Size(
      math.max(columnCount * characterAdvance, painter.width),
      math.max(rowCount * lineAdvance, painter.height),
    );
  }

  static const textStyle = TextStyle(
    fontFamily: 'AsciiCode',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Color(0xFF171A17),
    letterSpacing: 0,
    wordSpacing: 0,
    fontFeatures: [
      FontFeature.disable('liga'),
      FontFeature.disable('calt'),
      FontFeature.disable('kern'),
    ],
  );

  final String text;
  final int rowCount;
  final int columnCount;
  final List<int> _rowStarts = [];
  final List<List<int>> _cellStarts = [];
  late final TextPainter painter;
  late final double characterAdvance;
  late final double lineAdvance;
  late final Size size;

  math.Point<int>? cellAt(Offset point) {
    if (!(Offset.zero & size).contains(point)) return null;
    final glyph = painter.getClosestGlyphForOffset(point);
    if (glyph == null) return null;
    final offset = glyph.graphemeClusterCodeUnitRange.start;
    for (var row = _rowStarts.length - 1; row >= 0; row--) {
      if (offset < _rowStarts[row]) continue;
      final cells = _cellStarts[row];
      for (var column = cells.length - 1; column >= 0; column--) {
        if (offset >= cells[column]) return math.Point(column, row);
      }
      return null;
    }
    return null;
  }

  List<Rect> selectionRects(int left, int top, int right, int bottom) {
    final rects = <Rect>[];
    for (var row = top; row <= bottom; row++) {
      final start = _cellStarts[row][left];
      final end = right + 1 < columnCount
          ? _cellStarts[row][right + 1]
          : row + 1 < rowCount
              ? _rowStarts[row + 1] - 1
              : text.length;
      for (final box in painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end))) {
        rects.add(box.toRect());
      }
    }
    return rects;
  }

  void paint(Canvas canvas) => painter.paint(canvas, Offset.zero);

  void dispose() => painter.dispose();
}
