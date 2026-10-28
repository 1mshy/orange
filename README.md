# Orange 🍊

**The zero-click offline file converter for macOS, open source.**

Drag a file, tap a modifier key, and drop it on the format you need. Orange is a
menu-bar app that reconstructs the workflow of the commercial app *Tangerine*
without subscriptions, usage limits or network access. Everything runs locally.

```
   drag a file  →  tap ⇧  →  drop on a petal
                   tap ⌘  →  file tools (compress, crop, trim, split, merge…)
                   tap ⌃  →  file actions (AirDrop, Float, Copy, Move, Copy Path, Terminal)
```

Release the key and keep dragging: the wheel stays open until you drop or press
Escape. Arrow keys choose a petal, Return applies it. No Accessibility
permission is required: Orange watches the system drag pasteboard and polls
modifier state the same way Tangerine does.

## Formats

| Category | In | Out |
| --- | --- | --- |
| Images | JPG PNG WebP HEIC TIFF AVIF BMP GIF SVG (+RAW previews) | JPG PNG WebP HEIC TIFF AVIF BMP PDF |
| Video | MP4 MOV MKV WebM AVI WMV GIF M4V MPG … | MP4 MOV MKV WebM AVI WMV GIF, MP3 |
| Audio | MP3 M4A WAV FLAC OGG Opus AIFF WMA AAC … | MP3 M4A WAV FLAC OGG Opus AIFF WMA |
| PDF | PDF | DOCX PPTX\* XLSX\* JPG PNG WebP EPUB TXT MD HTML RTF |
| Documents | DOCX DOC\* Pages (preview) MD TXT RTF RTFD HTML text clippings ODT\* | PDF DOCX MD TXT EPUB HTML RTF |
| Slides | PPTX PPT ODP\* | PDF JPG PNG |
| Spreadsheets | XLSX ODS CSV TSV XLS\* | XLSX ODS CSV TSV PDF |
| EPUB | EPUB | PDF DOCX MD TXT HTML RTF |
| Subtitles | SRT VTT | SRT VTT TXT |
| Archives | ZIP TAR GZ TGZ BZ2 XZ RAR† 7z† | Extract, ZIP, TAR, GZIP |

\* needs LibreOffice · † needs `unar`

Images, PDF, documents, spreadsheets, subtitles and archives work with nothing
but macOS. Audio, video, GIF and AVIF need **ffmpeg**; WebP output needs
**cwebp** (or ffmpeg with libwebp):

```sh
brew install ffmpeg webp        # media + WebP
brew install unar               # optional: RAR / 7z
brew install --cask libreoffice # optional: PowerPoint, .doc, .xls, PDF→PPTX/XLSX
```

Orange looks in its own bundle (`Contents/Resources/Tools/`), `/opt/homebrew/bin`,
`/usr/local/bin` and `$PATH`, or at the path you set in Settings (or the
`ORANGE_FFMPEG` environment variable). Each candidate is launched once with
`-version`, so a Homebrew ffmpeg broken by a dylib upgrade is skipped rather
than failing every conversion; `brew reinstall ffmpeg` repairs that.

## File tools (⌘ wheel)

Compress (preset, target size or percentage, optional resize), Metadata (strip or
set title/author/copyright/keywords), Edit (exposure, brightness, contrast,
saturation, sharpness), Add BG (color, padding, corner radius, aspect), Crop
(aspect or exact rectangle), Redact (Vision face/text detection, solid or blur),
Create PDF, Collage, Trim, Split (time points or page ranges), Merge, Snapshot,
Speed, Normalize, Channels, Rotate, Mute.

## File actions (⌃ wheel)

AirDrop, Float (a floating shelf you can drag files out of later), Copy, Move,
Copy Path, Terminal / iTerm2.

## Install

Every push to `main` builds the app on GitHub Actions and publishes it under
[Releases](https://github.com/1mshy/orange/releases). Download the latest
`Orange-<version>-<build>.zip`, unzip it, move `Orange.app` to Applications and
clear the quarantine flag once (the build is ad-hoc signed, not notarized):

```sh
xattr -dr com.apple.quarantine /Applications/Orange.app
```

Media routes need `ffmpeg` on your PATH (`brew install ffmpeg`); office routes
fall back to LibreOffice if installed.

## Build

Requires Xcode 16+ and macOS 14+. The project file is generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Orange.xcodeproj -scheme Orange -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO
open build/Build/Products/Release/Orange.app
```

Or open `Orange.xcodeproj` in Xcode and run. The app is unsandboxed and ad-hoc
signed; set your own team in `project.yml` to notarize.

### Headless use and tests

The binary doubles as a CLI, which the smoke test uses:

```sh
Orange.app/Contents/MacOS/Orange --convert photo.heic webp ~/Desktop
Orange.app/Contents/MacOS/Orange --tool compress clip.mp4 --out ~/Desktop
Orange.app/Contents/MacOS/Orange --list
scripts/smoke-test.sh          # builds fixtures, runs ~50 conversions
```

## Project layout

```
Orange/
  App/            AppDelegate (menu-bar lifecycle), Welcome window, CLI mode
  Drag/           DragGestureMonitor: drag-pasteboard + CGEventSource polling
  Wheel/          WheelPanel, WheelView (petal fan), WheelController, model
  Formats/        FileCategory, FormatCatalog (the conversion matrix), tools, actions
  Conversion/     ConversionEngine + one converter per family
  Tools/          ToolOptions, ToolRunner (all 17 tools), options sheet
  Actions/        FileActions, FloatShelf
  Progress/       OperationCenter + floating progress window
  Settings/       AppSettings (modifiers, output location, terminal, login item)
docs/REVERSE-ENGINEERING.md   evidence ledger from the Tangerine analysis
```

## How it relates to Tangerine

Orange was built by studying Tangerine's shipped bundle (strings, Swift type
metadata, selector cross-references, bundled helpers and two decompiled
functions) and reimplementing the observed behaviour from scratch in Swift.
See `docs/REVERSE-ENGINEERING.md` for the full ledger, including what was
inferred and what remains unknown. Tangerine's own code, assets and bundled
tools are not part of this repository.

## License

MIT. See `LICENSE`.
