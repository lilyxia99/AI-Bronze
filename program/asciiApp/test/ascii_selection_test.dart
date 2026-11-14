import 'dart:math' as math;
import 'package:ascii_canvas/ascii_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overlapping moves snapshot source before clearing and include spaces',
      () {
    final grid = ['AB CD', '12345'].map((s) => s.split('')).toList();
    const area = AsciiSelection(0, 0, 2, 0);
    final result = area.move(grid, area.translated(1, 0, 5, 2));
    expect(result[0].join(), ' AB D');
    expect(result[1].join(), '12345');
    expect(grid[0].join(), 'AB CD');
  });
  test('reverse selection and edge moves preserve entire selection', () {
    final area =
        AsciiSelection.between(const math.Point(3, 2), const math.Point(1, 1));
    final target = area.translated(99, -99, 5, 4);
    expect(
        [target.left, target.top, target.right, target.bottom], [2, 0, 4, 1]);
  });
}
