#!/bin/zsh
# Generates small sample files used by scripts/smoke-test.sh.
# Media fixtures need any ffmpeg (set ORANGE_FFMPEG to pick one); no lavfi required.
set -e
cd "$(dirname "$0")/../fixtures"
swift - <<'SWIFT'
import AppKit
func frame(_ t: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: 320, height: 200)); img.lockFocus()
    NSColor.orange.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 200)).fill()
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 40 + 180 * t, y: 40, width: 100, height: 120)).fill()
    img.unlockFocus(); return img
}
func png(_ img: NSImage) -> Data { NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])! }
let still = frame(0.3)
try! png(still).write(to: URL(fileURLWithPath: "sample.png"))
try! NSBitmapImageRep(data: still.tiffRepresentation!)!.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: "sample.jpg"))
try? FileManager.default.createDirectory(atPath: "frames", withIntermediateDirectories: true)
for i in 0..<30 { try! png(frame(CGFloat(i) / 29)).write(to: URL(fileURLWithPath: String(format: "frames/f%03d.png", i))) }
// 2 s, 22050 Hz, 16-bit mono sine WAV
let rate = 22050, seconds = 2, n = rate * seconds
var pcm = Data(capacity: n * 2)
for i in 0..<n { var v = Int16(sin(Double(i) / Double(rate) * 440 * 2 * .pi) * 12000); pcm.append(Data(bytes: &v, count: 2)) }
var wav = Data()
func le32(_ v: Int) { var x = UInt32(v).littleEndian; wav.append(Data(bytes: &x, count: 4)) }
func le16(_ v: Int) { var x = UInt16(v).littleEndian; wav.append(Data(bytes: &x, count: 2)) }
wav.append("RIFF".data(using: .ascii)!); le32(36 + pcm.count); wav.append("WAVEfmt ".data(using: .ascii)!); le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
wav.append("data".data(using: .ascii)!); le32(pcm.count); wav.append(pcm)
try! wav.write(to: URL(fileURLWithPath: "sample.wav"))
SWIFT
printf 'name,qty,price\nApple,3,1.25\n"Pear, green",2,0.80\n' > sample.csv
printf '# Title\n\nSome **bold** and *italic* text.\n\n- one\n- two\n\n## Heading two\n\nParagraph.\n' > sample.md
printf '1\n00:00:01,000 --> 00:00:03,000\nHello\n\n2\n00:00:04,000 --> 00:00:06,500\nWorld\n' > sample.srt
printf 'Plain text document.\nSecond line.\n' > sample.txt
FFMPEG=${ORANGE_FFMPEG:-$(command -v ffmpeg)}
if [ -n "$FFMPEG" ] && "$FFMPEG" -version >/dev/null 2>&1; then
  "$FFMPEG" -y -hide_banner -loglevel error -framerate 15 -i frames/f%03d.png -i sample.wav -c:v mpeg4 -q:v 3 -pix_fmt yuv420p -c:a aac -shortest sample.mp4
else
  echo "no working ffmpeg: skipping sample.mp4"
fi
rm -rf frames
mkdir -p folder && cp sample.txt folder/
ditto -c -k --keepParent folder sample.zip
echo "fixtures ready"
