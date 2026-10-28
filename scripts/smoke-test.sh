#!/bin/zsh
# Runs the headless converter across the main routes. Usage: scripts/smoke-test.sh [path/to/Orange.app]
# Set ORANGE_FFMPEG=/path/to/ffmpeg to test media routes with a specific binary.
APP=${1:-build/Build/Products/Debug/Orange.app}
BIN="$APP/Contents/MacOS/Orange"
cd "$(dirname "$0")/.."
[ -x "$BIN" ] || { echo "build first: xcodebuild -project Orange.xcodeproj -scheme Orange -derivedDataPath build CODE_SIGNING_ALLOWED=NO"; exit 1; }
[ -f fixtures/sample.png ] || scripts/make-fixtures.sh
rm -rf fixtures/out && mkdir -p fixtures/out
pass=0; fail=0
run() { # run <file> <ext>
  if out=$("$BIN" --convert "fixtures/$1" "$2" fixtures/out 2>&1); then echo "ok    $1 → $2: $(basename "$(echo "$out" | head -1)")"; pass=$((pass+1));
  else echo "FAIL  $1 → $2: $out"; fail=$((fail+1)); fi
}
tool() { # tool <id> <files...>
  if out=$("$BIN" --tool "$@" --out fixtures/out 2>&1); then echo "ok    tool $1: $(basename "$(echo "$out" | head -1)")"; pass=$((pass+1));
  else echo "FAIL  tool $1: $out"; fail=$((fail+1)); fi
}
run sample.png jpg; run sample.png webp; run sample.png heic; run sample.png tiff; run sample.png bmp; run sample.png pdf; run sample.jpg png; run sample.png avif
run sample.md docx; run sample.md pdf; run sample.md html; run sample.md epub; run sample.txt rtf; run sample.md txt
run sample.csv xlsx; run sample.csv ods; run sample.csv tsv; run sample.csv pdf
run sample.srt vtt; run sample.srt txt
run sample.zip tar; run sample.zip extract; run sample.txt zip; run sample.txt gz
"$BIN" --convert fixtures/out/sample.docx md fixtures/out >/dev/null 2>&1 && echo "ok    docx → md" || echo "FAIL  docx → md"
"$BIN" --convert fixtures/out/sample.xlsx csv fixtures/out >/dev/null 2>&1 && echo "ok    xlsx → csv" || echo "FAIL  xlsx → csv"
"$BIN" --convert fixtures/out/sample.ods csv fixtures/out >/dev/null 2>&1 && echo "ok    ods → csv" || echo "FAIL  ods → csv"
"$BIN" --convert fixtures/out/sample.epub txt fixtures/out >/dev/null 2>&1 && echo "ok    epub → txt" || echo "FAIL  epub → txt"
"$BIN" --convert fixtures/out/sample.pdf png fixtures/out >/dev/null 2>&1 && echo "ok    pdf → png" || echo "FAIL  pdf → png"
"$BIN" --convert "fixtures/out/sample 2.pdf" docx fixtures/out >/dev/null 2>&1 && echo "ok    pdf → docx" || echo "FAIL  pdf → docx"
if [ -f fixtures/sample.wav ]; then
  run sample.wav mp3; run sample.wav flac; run sample.wav ogg; run sample.wav opus; run sample.wav m4a
  run sample.mp4 mov; run sample.mp4 webm; run sample.mp4 gif; run sample.mp4 mp3
  tool trim fixtures/sample.mp4; tool compress fixtures/sample.mp4; tool snapshot fixtures/sample.mp4; tool mute fixtures/sample.mp4; tool normalize fixtures/sample.wav
fi
tool compress fixtures/sample.jpg; tool metadata fixtures/sample.jpg; tool edit fixtures/sample.png; tool background fixtures/sample.png; tool crop fixtures/sample.png
tool rotate fixtures/sample.png; tool createpdf fixtures/sample.png fixtures/sample.jpg; tool collage fixtures/sample.png fixtures/sample.jpg; tool merge fixtures/out/sample.pdf "fixtures/out/sample 2.pdf"
echo "passed: $pass  failed: $fail"
