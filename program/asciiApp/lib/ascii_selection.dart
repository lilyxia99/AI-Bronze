import 'dart:math' as math;

/// Inclusive cell bounds. A move clears its source before writing its snapshot,
/// so overlapping moves preserve every character (including spaces).
class AsciiSelection {
  const AsciiSelection(this.left, this.top, this.right, this.bottom);

  factory AsciiSelection.between(math.Point<int> a, math.Point<int> b) =>
      AsciiSelection(math.min(a.x, b.x), math.min(a.y, b.y), math.max(a.x, b.x),
          math.max(a.y, b.y));

  final int left, top, right, bottom;
  int get width => right - left + 1;
  int get height => bottom - top + 1;

  bool contains(math.Point<int> cell) =>
      cell.x >= left && cell.x <= right && cell.y >= top && cell.y <= bottom;

  AsciiSelection translated(int dx, int dy, int columns, int rows) {
    final x = (left + dx).clamp(0, columns - width);
    final y = (top + dy).clamp(0, rows - height);
    return AsciiSelection(x, y, x + width - 1, y + height - 1);
  }

  List<List<String>> move(List<List<String>> grid, AsciiSelection target) {
    final result = grid.map((row) => List<String>.of(row)).toList();
    for (var r = top; r <= bottom; r++) {
      for (var c = left; c <= right; c++) {
        result[r][c] = ' ';
      }
    }
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width; c++) {
        result[target.top + r][target.left + c] = grid[top + r][left + c];
      }
    }
    return result;
  }
}
