# How Orange was reconstructed from Tangerine

Orange is a clean-room reimplementation of the *behaviour* of Tangerine 2.0.2
(`com.th.Tangerine`, Mac App Store build 9). No code, assets or strings from
Tangerine are included; the bundle was only inspected to understand what the
app does and how it detects drags. This file is the evidence ledger.

Target: `Tangerine.app/Contents/MacOS/Tangerine`, Mach-O arm64,
SHA-256 `7691b34cc2c728aaf280041c0a13adef3e5192c43cb3e886a19ae4c69ea92928`.
The binary is stripped (no Swift function symbols), so conclusions come from
Swift type metadata names, Objective-C selector references, bundled resources,
and two Hopper decompilations. Evidence IDs are REA session references.

## Architecture (observed)

| Area | Observation | Source |
| --- | --- | --- |
| App type | `LSUIElement = true`, `NSPrincipalClass = NSApplication`, min macOS 13, arm64 only, SwiftUI + AppKit | Info.plist, `otool -L` |
| Monetisation | RevenueCat SDK (`RevenueCatAPIKey` in Info.plist), `UsageCountStore` variants (Defaults/Keychain/Mirrored/InMemory), `PaywallWindowController`, `UnlockStore` | type metadata strings |
| Drag detection | `AppDelegate.dragGestureMonitor` is created with `NSPasteboard(name: .drag)`; its initial `changeCount` is stored; timer intervals `0.35` and `1/60` s are set up | Hopper pseudocode of `sub_100030108` (ev_ab95add5…) |
| Event sources | Imports `CGEventSourceButtonState`, `CGEventSourceFlagsState`, `CGEventSourceKeyState`; exactly one xref to `addGlobalMonitorForEventsMatchingMask:handler:` (`sub_10021e868`); no `CGEventTap` / `AXIsProcessTrusted` imports | `nm -u`, ev_1835d69c…, ev_68cd31fe…, ev_ca07c3ce…, ev_8022f73b… |
| Wheel UI | `ConversionOverlayPanel/Controller/View`, `NativeGlassFanView`, `NativePetalGlassShape`, `FanCenterLabelView`, `FormatDropTarget`, `FanHighlightSoundPlayer`, `ConversionFanTheme`, `WheelModifierSettings`, `DragModifierCombination` | type metadata |
| Windows | Welcome, Settings, Paywall, FileToolOptions, OperationProgress, FloatingFile (shelf), QRCodeResults | type metadata |
| Image I/O | ImageIO (`kCGImage…` keys), CoreImage adjustments, Vision (`VNBarcodeSymbology`, face/text detection for redaction), `PNGOptimizer` | linked frameworks, strings |
| WebP | bundled `Resources/Tools/cwebp`; also probes `/opt/homebrew/bin/cwebp` and `/usr/local/bin/cwebp` | bundle, strings |
| Audio/video | bundled `Resources/Tools/ffmpeg` (21 MB, LGPL notices); argument sets `-hide_banner -nostdin -loglevel error`, `-movflags +faststart`, `-tag:v hvc1`, `-c:a aac/libmp3lame/flac/pcm_s16le/pcm_s16be/opus/vorbis/wmav2`, `-b:a 192k/128k`, `-map_metadata -1`, `-map_chapters`, `-progress pipe:1 -nostats` with `out_time_`/`speed=` parsing, `libaom-av1`, `libvpx-vp9` | strings 30075–30320 |
| Metadata | bundled unmodified ExifTool Perl distribution with two bridge scripts `tangerine_metadata.pl` and `tangerine_privacy.pl` (fail-closed, Apple maker-note handling, XMP byte-range deletion) | bundle |
| Office | private JRE 21 (Amazon Corretto, arm64 + x86_64) with Apache POI 5.5.1, PDFBox 3.0.6 and `tangerine-powerpoint.jar` (`TangerinePowerPoint.toPDF/fromPDF`, `TangerineSpreadsheet` xlsx/ods/csv/tsv/pdf and `pdfToXlsx` via a `PDFTextStripper` subclass) | `javap -p` |
| Pages | JavaScriptCore running `PagesWriter.js` (cupertino-files 0.4.0, MIT) exposing `writePages/readPages/inspectPages`; `PagesTemplate.pages` | bundle |
| DOCX preview/PDF | `OfficePreview.js` (docx-preview + JSZip) rendered in WebKit, `OfficePDFRenderer`, own `SDDOCXReader/Writer`, `EPUBConverter`, `SDVectorRenderer` (SVG) with safety limits | bundle, strings |
| Other | `SubtitleConverter` (SRT/VTT/TXT), `ArchiveConverter` with `RAREntry` (own RAR reader), `TerminalFileAction` (Terminal / iTerm2 by bundle id `com.googlecode.iterm2`), `AirDropSharingController`, `FileClipboardController`, `FileMoveAction`, `LoginItemController` (SMAppService), `FolderAccessStore` (sandbox bookmarks) | type metadata, strings |

## Inferences

* Drag detection: left-mouse-down snapshots the drag pasteboard's change
  count; while the button is held a 60 Hz timer polls `CGEventSource` for
  button, modifier and key state. A change-count increase marks a file drag.
  This avoids Accessibility/Input Monitoring permissions, which is why the
  App Store build can work sandboxed. Orange's `DragGestureMonitor` follows
  this design.
* The wheel is a non-activating `NSPanel` positioned at the pointer; its
  content view is a drag destination (`FormatDropTarget`). Hover selects a
  petal, drop performs it, Escape cancels, arrows/Return pick via keyboard.
* The 0.35 s constant is most likely a hold/animation delay; Orange uses a
  0.25 s grace period after mouse-up before closing the wheel.

## Unknowns

* Exact petal geometry, materials and animation curves (SwiftUI, not
  recoverable from a stripped binary).
* Whether the `0.35` timer gates "hold briefly before dragging to convert" on
  touch screens, as the website describes.
* The specific ExifTool invocation arguments and the privacy script's JSON
  protocol were not traced.

## What Orange deliberately does differently

* No RevenueCat, usage counting, paywall or network code.
* No bundled ffmpeg/cwebp/JRE/ExifTool: Orange finds Homebrew or custom
  installs, and LibreOffice stands in for the Java/POI pipeline.
* Pages output is not implemented (it needs the cupertino-files writer).
* The visual editors (annotate, visual crop, timeline trim) are replaced by
  numeric option sheets in this first release.
