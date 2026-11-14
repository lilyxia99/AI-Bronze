import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preformatted_ascii.dart';
import 'ascii_selection.dart';

void main() => runApp(const AsciiCanvasApp());

const ink = Color(0xFF171A17);
const paper = Color(0xFFD5D1C5);
const moss = Color(0xFF71836A);

enum _CharacterMode { draw, reorder, select, delete }

class AsciiCanvasApp extends StatelessWidget {
  const AsciiCanvasApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ASCII Garden',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: paper,
          colorScheme: ColorScheme.fromSeed(seedColor: moss, surface: paper),
          fontFamily: 'Courier',
        ),
        home: const DrawingScreen(),
      );
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  static const defaultColumns = 36;
  static const defaultRows = 25;
  static const maxColumns = 120;
  static const maxRows = 100;
  static const maxCells = 10000;
  static const _paletteStorageKey = 'ascii_garden_palettes_v1';
  static const _selectedPaletteKey = 'ascii_garden_selected_palette_v1';
  static const _brushKey = 'ascii_garden_brush_v1';
  static const _brushSizeKey = 'ascii_garden_brush_size_v1';
  static const _defaultPalettes = <String, List<String>>{
    'Ink': ['@', '#', '%', '*', '+', '=', '-', ':', '.', '/', r'\', '_', '&'],
    'Nature': ['♣', '♠', '♧', '·'],
    'Soft': ['○', '◌', '◦', '·'],
    'Blocks': ['█', '▓', '▒', '░'],
  };

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final TextEditingController _customCharacterController =
      TextEditingController();
  late List<List<String>> grid;
  Map<String, List<String>> palettes = _makeDefaultPalettes();
  final List<_CanvasSnapshot> history = [];
  String palette = 'Ink';
  String brush = '@';
  int canvasColumns = defaultColumns;
  int canvasRows = defaultRows;
  int brushSize = 1;
  File? _currentCanvasFile;
  String? _currentCanvasName;
  bool _savingCanvas = false;
  bool erasing = false;
  bool movingCanvas = false;
  bool _selectingArt = false;
  AsciiSelection? _artSelection;
  AsciiSelection? _moveTarget;
  math.Point<int>? _selectionAnchor;
  Offset? _selectionDragStart;

  void _clearArtSelection() {
    _artSelection = null;
    _moveTarget = null;
    _selectionAnchor = null;
    _selectionDragStart = null;
  }

  void _startSelection(Offset position) {
    final cell = _preLayout?.cellAt(position);
    if (cell == null) return;
    setState(() {
      if (_artSelection?.contains(cell) ?? false) {
        _selectionDragStart = position;
        _moveTarget = _artSelection;
      } else {
        _selectionDragStart = null;
        _selectionAnchor = cell;
        _artSelection = AsciiSelection.between(cell, cell);
      }
    });
  }

  void _updateSelection(Offset position) {
    final layout = _preLayout;
    if (layout == null) return;
    setState(() {
      if (_selectionDragStart != null && _artSelection != null) {
        final delta = position - _selectionDragStart!;
        _moveTarget = _artSelection!.translated(
          (delta.dx / layout.characterAdvance).round(),
          (delta.dy / layout.lineAdvance).round(),
          canvasColumns,
          canvasRows,
        );
      } else if (_selectionAnchor != null) {
        final cell = layout.cellAt(Offset(
          position.dx.clamp(0.0, layout.size.width - 0.01),
          position.dy.clamp(0.0, layout.size.height - 0.01),
        ));
        if (cell != null) {
          _artSelection = AsciiSelection.between(_selectionAnchor!, cell);
        }
      }
    });
  }

  void _finishSelection() {
    setState(() {
      final source = _artSelection;
      final target = _moveTarget;
      if (source != null &&
          target != null &&
          (source.left != target.left || source.top != target.top)) {
        _saveUndo();
        grid = source.move(grid, target);
        _artSelection = target;
      }
      _moveTarget = null;
      _selectionAnchor = null;
      _selectionDragStart = null;
    });
  }

  _CharacterMode _characterMode = _CharacterMode.draw;
  final Set<String> _selectedCharacters = {};
  Size _viewportSize = Size.zero;
  Size _stageSize = Size.zero;
  bool _strokeHasUndo = false;
  PreformattedAsciiLayout? _preLayout;
  PreformattedAsciiLayout? _previewLayout;
  final TransformationController _transformController =
      TransformationController();

  static Map<String, List<String>> _makeDefaultPalettes() => {
        for (final entry in _defaultPalettes.entries)
          entry.key: List<String>.from(entry.value),
      };

  @override
  void initState() {
    super.initState();
    grid = _blankGrid();
    unawaited(_restorePreferences());
  }

  @override
  void dispose() {
    _customCharacterController.dispose();
    _transformController.dispose();
    _preLayout?.dispose();
    _previewLayout?.dispose();
    super.dispose();
  }

  List<List<String>> _blankGrid() =>
      List.generate(canvasRows, (_) => List.filled(canvasColumns, ' '));

  Future<void> _restorePreferences() async {
    try {
      final stored = await _preferences.getString(_paletteStorageKey);
      final selectedPalette = await _preferences.getString(_selectedPaletteKey);
      final storedBrush = await _preferences.getString(_brushKey);
      final storedSize = await _preferences.getInt(_brushSizeKey);

      Map<String, List<String>>? restored;
      if (stored != null) {
        final decoded = jsonDecode(stored);
        if (decoded is Map<String, dynamic>) {
          final candidate = <String, List<String>>{};
          for (final entry in decoded.entries) {
            final name = entry.key.trim();
            final values = entry.value;
            if (name.isEmpty || values is! List) continue;
            final characters = values.whereType<String>().toSet().toList();
            candidate[name] = characters;
          }
          if (candidate.isNotEmpty) restored = candidate;
        }
      }

      if (!mounted) return;
      setState(() {
        if (restored != null) palettes = restored;
        if (selectedPalette != null && palettes.containsKey(selectedPalette)) {
          palette = selectedPalette;
        }
        if (!palettes.containsKey(palette)) palette = palettes.keys.first;
        final available = palettes[palette]!;
        brush = storedBrush != null && available.contains(storedBrush)
            ? storedBrush
            : available.isEmpty
                ? ' '
                : available.first;
        erasing = available.isEmpty;
        brushSize = (storedSize ?? 1).clamp(1, 7);
      });
    } catch (_) {
      // Keep the built-in palettes if local preferences are unavailable or invalid.
    }
  }

  Future<void> _persistPreferences() async {
    await _preferences.setString(_paletteStorageKey, jsonEncode(palettes));
    await _preferences.setString(_selectedPaletteKey, palette);
    await _preferences.setString(_brushKey, brush);
    await _preferences.setInt(_brushSizeKey, brushSize);
  }

  void _saveUndo() {
    history.add(_CanvasSnapshot(
      columns: canvasColumns,
      rows: canvasRows,
      grid: grid.map((row) => List<String>.from(row)).toList(),
    ));
    if (history.length > 30) history.removeAt(0);
  }

  void _beginStroke(Offset point, Size size) {
    if (!_strokeHasUndo) {
      _saveUndo();
      _strokeHasUndo = true;
    }
    _paint(point, size);
  }

  void _paint(Offset point, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final cell = _preLayout?.cellAt(point);
    if (cell == null) return;
    final col = cell.x;
    final row = cell.y;

    final mark = erasing ? ' ' : brush;
    final startRow = row - ((brushSize - 1) ~/ 2);
    final startCol = col - ((brushSize - 1) ~/ 2);
    var changed = false;
    for (var r = startRow; r < startRow + brushSize; r++) {
      for (var c = startCol; c < startCol + brushSize; c++) {
        if (r < 0 || r >= canvasRows || c < 0 || c >= canvasColumns) {
          continue;
        }
        if (grid[r][c] == mark) continue;
        grid[r][c] = mark;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  String get artwork => grid.map((row) => row.join()).join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: artwork));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ASCII art copied to clipboard')),
    );
  }

  Future<void> _share(BuildContext shareContext) async {
    if (artwork.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw something before sharing')),
      );
      return;
    }

    final renderObject = shareContext.findRenderObject();
    final box = renderObject is RenderBox ? renderObject : null;
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'ASCII Garden',
          files: [
            XFile.fromData(utf8.encode(artwork), mimeType: 'text/plain'),
          ],
          fileNameOverrides: const ['ascii-garden.txt'],
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet')),
      );
    }
  }

  void _clear() {
    _saveUndo();
    _clearArtSelection();
    setState(() => grid = _blankGrid());
  }

  void _undo() {
    if (history.isEmpty) return;
    final previous = history.removeLast();
    setState(() {
      canvasColumns = previous.columns;
      canvasRows = previous.rows;
      _clearArtSelection();
      grid = previous.grid;
    });
    _transformController.value = Matrix4.identity();
  }

  Future<void> _editCanvasSize() async {
    var columnsText = canvasColumns.toString();
    var rowsText = canvasRows.toString();
    final shouldResize = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Canvas size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: columnsText,
                    onChanged: (value) => columnsText = value,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Columns'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: rowsText,
                    onChanged: (value) => rowsText = value,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Rows'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Up to 120 columns, 100 rows, and 10,000 cells. Larger canvases can be moved and zoomed.',
              style: TextStyle(fontSize: 12, color: Color(0xFF555B50)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Resize'),
          ),
        ],
      ),
    );

    final nextColumns = int.tryParse(columnsText);
    final nextRows = int.tryParse(rowsText);
    if (shouldResize != true || !mounted) return;
    if (nextColumns == null ||
        nextRows == null ||
        nextColumns < 4 ||
        nextColumns > maxColumns ||
        nextRows < 4 ||
        nextRows > maxRows ||
        nextColumns * nextRows > maxCells) {
      _showMessage('Choose valid dimensions within the 10,000-cell limit');
      return;
    }
    if (nextColumns == canvasColumns && nextRows == canvasRows) return;

    _saveUndo();
    final resized = List.generate(
      nextRows,
      (r) => List.generate(
        nextColumns,
        (c) => r < canvasRows && c < canvasColumns ? grid[r][c] : ' ',
      ),
    );
    setState(() {
      canvasColumns = nextColumns;
      canvasRows = nextRows;
      _clearArtSelection();
      grid = resized;
    });
    _transformController.value = Matrix4.identity();
  }

  Future<Directory> _canvasDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final canvasDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}Canvases',
    );
    await canvasDirectory.create(recursive: true);
    return canvasDirectory;
  }

  Map<String, Object> _canvasDocument(String name) => {
        'format': 'ascii-garden',
        'version': 1,
        'name': name,
        'columns': canvasColumns,
        'rows': canvasRows,
        'palette': palette,
        'brush': brush,
        'brushSize': brushSize,
        'grid': grid,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  Future<void> _saveCanvasFile({bool saveAs = false}) async {
    if (_savingCanvas) return;
    _savingCanvas = true;
    try {
      if (!saveAs && _currentCanvasFile != null) {
        await _writeCanvasFile(_currentCanvasFile!, _currentCanvasName!);
        if (mounted) _showMessage('Saved "$_currentCanvasName"');
        return;
      }
      await _saveCanvasAs();
    } catch (_) {
      if (mounted) _showMessage('Could not save this canvas');
    } finally {
      _savingCanvas = false;
    }
  }

  Future<void> _writeCanvasFile(File file, String name) async {
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(_canvasDocument(name)),
          flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _saveCanvasAs() async {
    var canvasName = _currentCanvasName == null
        ? 'My ASCII canvas'
        : '$_currentCanvasName copy';
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(_currentCanvasFile == null ? 'Save canvas' : 'Save canvas as'),
        content: TextFormField(
          initialValue: canvasName,
          onChanged: (value) => canvasName = value,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Canvas name'),
          onFieldSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final name = canvasName.trim();
    if (shouldSave != true || !mounted) return;
    if (name.isEmpty) {
      _showMessage('Enter a name for this canvas');
      return;
    }

    try {
      final directory = await _canvasDirectory();
      final safeName = name.replaceAll(RegExp(r'[/\\:]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(
        '${directory.path}${Platform.pathSeparator}$safeName-$stamp.asciigarden',
      );
      await _writeCanvasFile(file, name);
      if (!mounted) return;
      setState(() {
        _currentCanvasFile = file;
        _currentCanvasName = name;
      });
      _showMessage('Saved "$name" to My Canvases');
    } catch (_) {
      if (mounted) _showMessage('Could not save this canvas');
    }
  }

  Future<List<_SavedCanvasFile>> _readSavedCanvasFiles() async {
    final directory = await _canvasDirectory();
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => file.path.endsWith('.asciigarden'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));

    final saved = <_SavedCanvasFile>[];
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final name = decoded['name'];
        final columns = decoded['columns'];
        final rows = decoded['rows'];
        if (name is! String || columns is! int || rows is! int) continue;
        saved.add(_SavedCanvasFile(
          file: file,
          name: name,
          columns: columns,
          rows: rows,
        ));
      } catch (_) {
        // Skip an unreadable or incomplete project file.
      }
    }
    return saved;
  }

  Future<void> _openSavedCanvasFiles() async {
    try {
      final savedFiles = await _readSavedCanvasFiles();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('My Canvases'),
            content: SizedBox(
              width: 380,
              height: savedFiles.isEmpty
                  ? 90
                  : math.min(400.0, savedFiles.length * 72.0),
              child: savedFiles.isEmpty
                  ? const Center(
                      child: Text('Saved canvases will appear here'),
                    )
                  : ListView.separated(
                      itemCount: savedFiles.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final saved = savedFiles[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(saved.name),
                          subtitle:
                              Text('${saved.columns} × ${saved.rows} canvas'),
                          onTap: () async {
                            Navigator.pop(dialogContext);
                            await _loadCanvasFile(saved.file);
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Share project file',
                                onPressed: () => _shareCanvasFile(saved.file),
                                icon: const Icon(Icons.ios_share_rounded),
                              ),
                              IconButton(
                                tooltip: 'Delete saved canvas',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: dialogContext,
                                    builder: (confirmContext) => AlertDialog(
                                      title: const Text('Delete saved canvas?'),
                                      content: Text('Delete "${saved.name}"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                              confirmContext, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                              confirmContext, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await saved.file.delete();
                                    if (_currentCanvasFile?.path ==
                                        saved.file.path) {
                                      setState(() {
                                        _currentCanvasFile = null;
                                        _currentCanvasName = null;
                                      });
                                    }
                                    setDialogState(
                                        () => savedFiles.removeAt(index));
                                  }
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) _showMessage('Could not open saved canvases');
    }
  }

  Future<void> _loadCanvasFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid canvas document');
      }
      final columns = decoded['columns'];
      final rows = decoded['rows'];
      final savedGrid = decoded['grid'];
      if (columns is! int ||
          rows is! int ||
          columns < 4 ||
          columns > maxColumns ||
          rows < 4 ||
          rows > maxRows ||
          columns * rows > maxCells ||
          savedGrid is! List) {
        throw const FormatException('Invalid canvas dimensions');
      }

      final restoredGrid = List.generate(
        rows,
        (r) => List.generate(columns, (c) {
          if (r >= savedGrid.length || savedGrid[r] is! List) return ' ';
          final savedRow = savedGrid[r] as List;
          if (c >= savedRow.length || savedRow[c] is! String) return ' ';
          return savedRow[c] as String;
        }),
      );
      final savedPalette = decoded['palette'];
      final savedBrush = decoded['brush'];
      final savedBrushSize = decoded['brushSize'];
      setState(() {
        canvasColumns = columns;
        canvasRows = rows;
        _clearArtSelection();
        grid = restoredGrid;
        _currentCanvasFile = file;
        final name = decoded['name'];
        _currentCanvasName =
            name is String && name.trim().isNotEmpty ? name : 'My ASCII canvas';
        history.clear();
        movingCanvas = false;
        _characterMode = _CharacterMode.draw;
        _selectedCharacters.clear();
        if (savedPalette is String && palettes.containsKey(savedPalette)) {
          palette = savedPalette;
        }
        if (savedBrush is String && palettes[palette]!.contains(savedBrush)) {
          brush = savedBrush;
        } else {
          brush = palettes[palette]!.isEmpty ? ' ' : palettes[palette]!.first;
        }
        if (savedBrushSize is int) brushSize = savedBrushSize.clamp(1, 7);
        erasing = false;
      });
      _transformController.value = Matrix4.identity();
      await _persistPreferences();
      if (mounted) _showMessage('Opened canvas');
    } catch (_) {
      if (mounted) _showMessage('Could not open this canvas file');
    }
  }

  Future<void> _shareCanvasFile(File file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'Share ASCII Garden project',
          files: [XFile(file.path, mimeType: 'application/json')],
          fileNameOverrides: [file.uri.pathSegments.last],
        ),
      );
    } catch (_) {
      if (mounted) _showMessage('Could not share this canvas file');
    }
  }

  Widget _buildCanvas(Size viewportSize) {
    _preLayout?.dispose();
    _previewLayout?.dispose();
    final layout = PreformattedAsciiLayout(grid);
    _preLayout = layout;
    final canvasSize = layout.size;
    final stageWidth = math.max(viewportSize.width, canvasSize.width);
    final stageHeight = math.max(viewportSize.height, canvasSize.height);
    _viewportSize = viewportSize;
    _stageSize = Size(stageWidth, stageHeight);
    final left = (stageWidth - canvasSize.width) / 2;
    final top = (stageHeight - canvasSize.height) / 2;
    _previewLayout = _moveTarget != null && _artSelection != null
        ? PreformattedAsciiLayout(_artSelection!.move(grid, _moveTarget!))
        : null;
    final drawingSurface = CustomPaint(
      size: canvasSize,
      painter: AsciiPrePainter(_previewLayout ?? layout,
          selection: _selectingArt ? (_moveTarget ?? _artSelection) : null),
    );

    return InteractiveViewer(
      transformationController: _transformController,
      constrained: false,
      alignment: Alignment.topLeft,
      panEnabled: movingCanvas,
      scaleEnabled: movingCanvas,
      minScale: 0.1,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(100),
      child: SizedBox(
        width: stageWidth,
        height: stageHeight,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: canvasSize.width,
              height: canvasSize.height,
              child: movingCanvas
                  ? drawingSurface
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (event) => _selectingArt
                          ? _startSelection(event.localPosition)
                          : _beginStroke(event.localPosition, canvasSize),
                      onPanUpdate: (event) => _selectingArt
                          ? _updateSelection(event.localPosition)
                          : _paint(event.localPosition, canvasSize),
                      onPanEnd: (_) {
                        if (_selectingArt) _finishSelection();
                        _strokeHasUndo = false;
                      },
                      onPanCancel: () {
                        setState(() {
                          _moveTarget = null;
                          _selectionDragStart = null;
                          _selectionAnchor = null;
                          _strokeHasUndo = false;
                        });
                      },
                      onTapDown: (event) {
                        if (!_selectingArt) {
                          _beginStroke(event.localPosition, canvasSize);
                        }
                      },
                      onTapUp: (event) {
                        if (_selectingArt) {
                          _startSelection(event.localPosition);
                          _finishSelection();
                        }
                        _strokeHasUndo = false;
                      },
                      onTapCancel: () => _strokeHasUndo = false,
                      child: drawingSurface,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectPalette(String name) {
    final characters = palettes[name];
    if (characters == null) return;
    setState(() {
      palette = name;
      _characterMode = _CharacterMode.draw;
      _selectedCharacters.clear();
      brush = characters.isEmpty ? ' ' : characters.first;
      erasing = characters.isEmpty;
    });
    unawaited(_persistPreferences());
  }

  List<String> _charactersFrom(String text) {
    final seen = <String>{};
    return text.runes
        .map(String.fromCharCode)
        .where(
            (character) => character.trim().isNotEmpty && seen.add(character))
        .toList();
  }

  Future<void> _addPalette() async {
    var paletteName = '';
    var paletteCharacters = '';
    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New palette'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              onChanged: (value) => paletteName = value,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Palette name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              onChanged: (value) => paletteCharacters = value,
              decoration: const InputDecoration(
                labelText: 'Characters',
                hintText: 'e.g. /\\_&',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add palette'),
          ),
        ],
      ),
    );

    final name = paletteName.trim();
    final characters = _charactersFrom(paletteCharacters);
    if (shouldAdd != true || !mounted) return;

    if (name.isEmpty || characters.isEmpty) {
      _showMessage('Enter a name and at least one character');
      return;
    }
    if (palettes.keys
        .any((existing) => existing.toLowerCase() == name.toLowerCase())) {
      _showMessage('A palette with that name already exists');
      return;
    }

    setState(() {
      palettes[name] = characters;
      palette = name;
      _characterMode = _CharacterMode.draw;
      _selectedCharacters.clear();
      brush = characters.isEmpty ? ' ' : characters.first;
      erasing = characters.isEmpty;
    });
    await _persistPreferences();
  }

  Future<void> _removePalette(String name) async {
    if (palettes.length <= 1) {
      _showMessage('Keep at least one palette');
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete palette?'),
        content: Text('Remove "$name" and its saved characters?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() {
      palettes.remove(name);
      _characterMode = _CharacterMode.draw;
      _selectedCharacters.clear();
      if (palette == name) {
        palette = palettes.keys.first;
        brush = palettes[palette]!.isEmpty ? ' ' : palettes[palette]!.first;
        erasing = false;
      }
    });
    await _persistPreferences();
  }

  void _centerCanvas() {
    if (_stageSize.isEmpty || _viewportSize.isEmpty) return;
    final scale = math.min(
      1.0,
      math.min(_viewportSize.width / _stageSize.width,
          _viewportSize.height / _stageSize.height),
    );
    final x = (_viewportSize.width - _stageSize.width * scale) / 2;
    final y = (_viewportSize.height - _stageSize.height * scale) / 2;
    _transformController.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(x, y, 0);
  }

  void _setCharacterMode(_CharacterMode mode) {
    FocusScope.of(context).unfocus();
    setState(() {
      _characterMode = _characterMode == mode ? _CharacterMode.draw : mode;
      _selectedCharacters.clear();
    });
  }

  void _tapCharacter(String character) {
    if (_characterMode == _CharacterMode.select) {
      setState(() {
        if (!_selectedCharacters.add(character)) {
          _selectedCharacters.remove(character);
        }
      });
    } else if (_characterMode == _CharacterMode.delete) {
      unawaited(_deleteCharacters({character}));
    } else {
      setState(() {
        brush = character;
        erasing = false;
      });
      unawaited(_persistPreferences());
    }
  }

  void _reorderCharacters(int oldIndex, int newIndex) {
    setState(() {
      final characters = palettes[palette]!;
      characters.insert(newIndex, characters.removeAt(oldIndex));
    });
    unawaited(_persistPreferences());
  }

  void _pressDelete() {
    if (_characterMode == _CharacterMode.select &&
        _selectedCharacters.isNotEmpty) {
      unawaited(_deleteCharacters(Set.of(_selectedCharacters)));
    } else {
      _setCharacterMode(_CharacterMode.delete);
    }
  }

  Future<void> _deleteCharacters(Set<String> characters) async {
    final targetPalette = palette;
    final before = List<String>.from(palettes[targetPalette]!);
    final remaining = before.where((c) => !characters.contains(c)).toList();
    final previousBrush = brush;
    final wasErasing = erasing;
    setState(() {
      palettes[targetPalette] = remaining;
      _selectedCharacters.clear();
      if (!remaining.contains(brush)) {
        brush = remaining.isEmpty ? ' ' : remaining.first;
      }
      if (remaining.isEmpty) erasing = true;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content:
            Text('Removed ${before.length - remaining.length} character(s)'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!palettes.containsKey(targetPalette)) return;
            setState(() {
              palettes[targetPalette] = before;
              if (palette == targetPalette) {
                brush = previousBrush;
                erasing = wasErasing;
              }
              _selectedCharacters.clear();
            });
            unawaited(_persistPreferences());
          },
        ),
      ));
    await _persistPreferences();
  }

  Future<void> _addCustomCharacter() async {
    final characters = _charactersFrom(_customCharacterController.text);
    if (characters.length != 1) {
      _showMessage('Enter one character to add');
      return;
    }
    final character = characters.single;
    setState(() {
      if (!palettes[palette]!.contains(character)) {
        palettes[palette]!.add(character);
      }
      brush = character;
      erasing = false;
      _characterMode = _CharacterMode.draw;
      _selectedCharacters.clear();
    });
    _customCharacterController.clear();
    await _persistPreferences();
    if (mounted) _showMessage('Saved to $palette');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _characterToolButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        tooltip: tooltip,
        isSelected: active,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: active ? ink : Colors.transparent,
          foregroundColor: active ? paper : ink,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
      );

  Widget _buildCharacterStrip() {
    final characters = palettes[palette]!;
    final selecting = _characterMode == _CharacterMode.select;
    final deleting = _characterMode == _CharacterMode.delete;
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 18, right: 4),
              buildDefaultDragHandles: false,
              itemCount: characters.length,
              itemExtent: 49,
              onReorderItem: _reorderCharacters,
              itemBuilder: (context, index) {
                final character = characters[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('$palette:$character'),
                  index: index,
                  enabled: !selecting && !deleting,
                  child: _BrushButton(
                    label: character == ' ' ? '·' : character,
                    selected: selecting
                        ? _selectedCharacters.contains(character)
                        : !erasing && brush == character,
                    selectionMode: selecting,
                    deletionMode: deleting,
                    tooltip: deleting
                        ? 'Delete $character'
                        : selecting
                            ? 'Select $character'
                            : 'Use $character; hold and drag to reorder',
                    onTap: () => _tapCharacter(character),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 11),
            child: _BrushButton(
              label: '⌫',
              selected: erasing,
              tooltip: 'Erase canvas',
              onTap: () => setState(() {
                erasing = !erasing;
                _characterMode = _CharacterMode.draw;
                _selectedCharacters.clear();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterModeHint() {
    final selecting = _characterMode == _CharacterMode.select;
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 12),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            Expanded(
              child: Text(
                selecting
                    ? '${_selectedCharacters.length} selected · tap the bin to delete'
                    : _characterMode == _CharacterMode.delete
                        ? 'Delete mode · tap a character to remove'
                        : 'Hold and drag a character to reorder',
                style: const TextStyle(fontSize: 10, color: Color(0xFF555B50)),
              ),
            ),
            if (selecting)
              TextButton(
                onPressed: () => setState(() {
                  if (_selectedCharacters.length == palettes[palette]!.length) {
                    _selectedCharacters.clear();
                  } else {
                    _selectedCharacters.addAll(palettes[palette]!);
                  }
                }),
                child: Text(
                    _selectedCharacters.length == palettes[palette]!.length
                        ? 'None'
                        : 'All'),
              ),
            TextButton(
              onPressed: () => setState(() {
                _characterMode = _CharacterMode.draw;
                _selectedCharacters.clear();
              }),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = history.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 15, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: const Text('A_',
                        style: TextStyle(color: paper, fontSize: 17)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ASCII GARDEN',
                            style: TextStyle(
                                color: ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3)),
                        SizedBox(height: 3),
                        Text('A little art, one character at a time',
                            style: TextStyle(
                                color: Color(0xFF555B50), fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Open saved canvases',
                    onPressed: _openSavedCanvasFiles,
                    icon: const Icon(Icons.folder_open_rounded, size: 19),
                  ),
                  Tooltip(
                    message: 'Save canvas',
                    triggerMode: TooltipTriggerMode.manual,
                    child: GestureDetector(
                      onLongPress: () => _saveCanvasFile(saveAs: true),
                      child: IconButton.filledTonal(
                        onPressed: () => _saveCanvasFile(),
                        icon: const Icon(Icons.save_outlined, size: 19),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (shareContext) => IconButton.filledTonal(
                      tooltip: 'Share or AirDrop as a text file',
                      onPressed: () => _share(shareContext),
                      icon: const Icon(Icons.ios_share_rounded, size: 19),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: DecoratedBox(
                        decoration:
                            const BoxDecoration(color: Color(0xFFBBB7AA)),
                        child: _buildCanvas(
                          Size(constraints.maxWidth, constraints.maxHeight),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 12, 0),
              child: Row(
                children: [
                  Icon(
                    movingCanvas
                        ? Icons.pan_tool_alt_rounded
                        : Icons.touch_app_rounded,
                    size: 16,
                    color: moss,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      movingCanvas
                          ? 'Drag or pinch to move'
                          : _selectingArt
                              ? 'Select an area, then drag it to move'
                              : 'Touch and drag to draw',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF555B50), fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _editCanvasSize,
                    icon: const Icon(Icons.aspect_ratio_rounded, size: 16),
                    label: Text('$canvasColumns × $canvasRows'),
                  ),
                  IconButton(
                    tooltip: 'Center and fit canvas',
                    visualDensity: VisualDensity.compact,
                    onPressed: _centerCanvas,
                    icon:
                        const Icon(Icons.center_focus_strong_rounded, size: 19),
                  ),
                  IconButton.filledTonal(
                    tooltip: _selectingArt
                        ? 'Finish selection'
                        : 'Select and move art',
                    visualDensity: VisualDensity.compact,
                    isSelected: _selectingArt,
                    onPressed: () => setState(() {
                      _selectingArt = !_selectingArt;
                      movingCanvas = false;
                      _clearArtSelection();
                    }),
                    icon: const Icon(Icons.select_all_rounded, size: 18),
                    selectedIcon: const Icon(Icons.check_rounded, size: 18),
                  ),
                  const SizedBox(width: 2),
                  IconButton.filledTonal(
                    tooltip: movingCanvas ? 'Switch to drawing' : 'Move canvas',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      movingCanvas = !movingCanvas;
                      _selectingArt = false;
                      _clearArtSelection();
                    }),
                    icon: Icon(
                      movingCanvas
                          ? Icons.edit_rounded
                          : Icons.pan_tool_alt_rounded,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 5),
              child: Row(
                children: [
                  const Text('PALETTE', style: _sectionStyle),
                  const SizedBox(width: 9),
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: palettes.keys
                            .map((name) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onLongPress: () => _removePalette(name),
                                    child: ChoiceChip(
                                      label: Text(name),
                                      selected: palette == name,
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) => _selectPalette(name),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add a palette',
                    visualDensity: VisualDensity.compact,
                    onPressed: _addPalette,
                    icon:
                        const Icon(Icons.add_circle_outline_rounded, size: 22),
                  ),
                ],
              ),
            ),
            _buildCharacterStrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customCharacterController,
                      textAlign: TextAlign.center,
                      maxLength: 8,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addCustomCharacter(),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Type one character ↵',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  _characterToolButton(
                    icon: Icons.swap_horiz_rounded,
                    tooltip: 'Reorder characters: hold and drag',
                    active: _characterMode == _CharacterMode.reorder,
                    onPressed: () => _setCharacterMode(_CharacterMode.reorder),
                  ),
                  _characterToolButton(
                    icon: Icons.checklist_rounded,
                    tooltip: 'Select multiple characters',
                    active: _characterMode == _CharacterMode.select,
                    onPressed: () => _setCharacterMode(_CharacterMode.select),
                  ),
                  _characterToolButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: _selectedCharacters.isEmpty
                        ? 'Delete mode: tap a character to remove it'
                        : 'Delete ${_selectedCharacters.length} selected characters',
                    active: _characterMode == _CharacterMode.delete,
                    onPressed: _pressDelete,
                  ),
                ],
              ),
            ),
            if (_characterMode != _CharacterMode.draw)
              _buildCharacterModeHint(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 3, 18, 2),
              child: Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text('BRUSH SIZE', style: _sectionStyle),
                  ),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 7,
                      divisions: 6,
                      value: brushSize.toDouble(),
                      onChanged: (value) =>
                          setState(() => brushSize = value.round()),
                      onChangeEnd: (_) => unawaited(_persistPreferences()),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('$brushSize×$brushSize',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            color: Color(0xFF555B50), fontSize: 11)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 13),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canUndo ? _undo : null,
                      icon: const Icon(Icons.undo_rounded, size: 17),
                      label: const Text('Undo'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy art'),
                      style: FilledButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: paper,
                        textStyle: const TextStyle(fontSize: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _sectionStyle = TextStyle(
    color: Color(0xFF555B50),
    fontSize: 9,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1);

class _CanvasSnapshot {
  const _CanvasSnapshot({
    required this.columns,
    required this.rows,
    required this.grid,
  });

  final int columns;
  final int rows;
  final List<List<String>> grid;
}

class _SavedCanvasFile {
  const _SavedCanvasFile({
    required this.file,
    required this.name,
    required this.columns,
    required this.rows,
  });

  final File file;
  final String name;
  final int columns;
  final int rows;
}

class _BrushButton extends StatelessWidget {
  const _BrushButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tooltip,
    this.selectionMode = false,
    this.deletionMode = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;
  final bool selectionMode;
  final bool deletionMode;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: Tooltip(
          message: tooltip,
          triggerMode: TooltipTriggerMode.manual,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 42,
              decoration: BoxDecoration(
                color: deletionMode
                    ? const Color(0xFFE1BDB2)
                    : selected
                        ? ink
                        : const Color(0xFFC4C0B3),
                borderRadius: BorderRadius.circular(11),
                border: deletionMode
                    ? Border.all(color: const Color(0xFF843E34))
                    : null,
              ),
              alignment: Alignment.center,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(label,
                        style: TextStyle(
                            color: selected && !deletionMode ? paper : ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (selectionMode && selected || deletionMode)
                    Positioned(
                      right: 3,
                      top: 3,
                      child: Icon(
                        deletionMode
                            ? Icons.remove_circle_rounded
                            : Icons.check_circle_rounded,
                        size: 12,
                        color: deletionMode ? const Color(0xFF843E34) : paper,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class AsciiPrePainter extends CustomPainter {
  AsciiPrePainter(this.layout, {this.selection});
  final PreformattedAsciiLayout layout;
  final AsciiSelection? selection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE6E1D4));
    // Guides follow actual text bounds without changing advances or baselines.
    final guides = Path();
    for (var row = 0; row < layout.rowCount; row++) {
      for (var column = 0; column < layout.columnCount; column++) {
        for (final rect in layout.selectionRects(column, row, column, row)) {
          guides.addRect(rect);
        }
      }
    }
    canvas.drawPath(
        guides,
        Paint()
          ..color = const Color(0x1871836A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6);
    layout.paint(canvas);
    final area = selection;
    if (area != null) {
      // Use the text's actual glyph boxes, including wider Unicode characters.
      final rects =
          layout.selectionRects(area.left, area.top, area.right, area.bottom);
      for (final rect in rects) {
        canvas.drawRect(rect, Paint()..color = const Color(0x3371836A));
        canvas.drawRect(
            rect.deflate(0.75),
            Paint()
              ..color = moss
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AsciiPrePainter oldDelegate) => true;
}
