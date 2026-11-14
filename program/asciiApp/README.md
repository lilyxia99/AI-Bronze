# ASCII Garden

A touch-first ASCII drawing app built with Flutter. Draw by touching and dragging, set a 1×1 to 7×7 brush, resize the canvas, center and fit it with one tap, and switch to Move mode to pan or pinch-zoom without drawing. Save named editable `.asciigarden` canvases on the iPhone, reopen them from My Canvases, or share a project file or `.txt` artwork through the iOS share sheet and AirDrop.

Hold a palette tab to delete that palette. Hold and drag a character to reorder it. Use the bin button to enter single-character deletion mode, or select multiple characters with the checklist button and then tap the bin. Deletions have an Undo action. Type one character and press Return to save it into the current palette. Palette changes and saved canvases are stored on the phone.

## Run on iPhone

Flutter and the iOS Runner project are configured on the development Mac. Because this folder is inside iCloud Drive, build from a local copy outside the synced folder to avoid iCloud Finder metadata interfering with framework signing. The Runner target uses the Apple development team selected in Xcode on this Mac.

The first install is on the phone. To open it, trust the developer profile under **Settings → General → VPN & Device Management** if iOS prompts for trust. Developer Mode is already enabled on the connected iPhone.

## Preformatted rendering

The canvas renders one unwrapped block of text using the bundled Roboto Mono Regular font at 14 logical pixels and its natural line height. Spaces (including trailing spaces), blank lines, and newlines are preserved. There is no per-character centering or width/height stretching. Touch hit testing uses the same text layout, including the character positions of fallback Unicode glyphs.

For a browser comparison, load `assets/fonts/RobotoMono-Regular.ttf` with `@font-face` as `AsciiCode`, then use:

```css
pre {
  font-family: AsciiCode, monospace;
  font-size: 14px;
  line-height: normal;
  white-space: pre;
  letter-spacing: 0;
  word-spacing: 0;
  font-kerning: none;
  font-variant-ligatures: none;
}
```

Canvas dimensions count stored character cells. Non-ASCII characters use the font's native glyph width, like preformatted text, rather than being squeezed into one ASCII column.

### Select and move art

Tap the selection icon beside the canvas controls. Drag to select a rectangular area, then drag inside it to move the characters with a live preview. The whole rectangle includes spaces and replaces its destination. Moves stop at canvas edges, clear the source, and can be undone. Drag outside the current selection to start a new one; tap the checkmark to return to drawing.

### Save and Save As

Tap Save to update the currently open draft. A new canvas asks for a name on its first save. Long-press Save to create a separate copy; later taps update that copy. Opening an older draft makes it the current save target. Writes replace the file only after the complete new document has been written.
