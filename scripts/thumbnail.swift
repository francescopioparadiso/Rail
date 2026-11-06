// Turns a screenshot into an App Store thumbnail laid out like the original
// App Store thumbnail: a two-line title over the device's bezel holding the screenshot.
//
// thumbnail <device> <screenshot.png> <out.png> "<line 1>" "<line 2>" [bezel color]
//   device: "iPhone 18 Pro" (1206 × 2622), "iPhone Duo" (folded, 1398 × 2034), or
//           "iPhone Duo Open" (opened out, landscape screenshot, 1080 × 1350 LinkedIn post)
//   lines:  SF Pro; a part between *stars* is New York semibold italic
//   colors: iPhone 18 Pro Black, Burgundy, Glacier, Silver (default);
//           iPhone Duo Night Sky (default), Star White (Images/Resources/Bezels)
import AppKit

let args = CommandLine.arguments
guard args.count >= 6 else {
    print("usage: thumbnail <device> <screenshot.png> <out.png> \"<line 1>\" \"<line 2>\" [bezel color]")
    exit(1)
}
let device = args[1]
let canvas: CGSize, defaultColor: String
switch device {
case "iPhone 18 Pro": canvas = CGSize(width: 1206, height: 2622); defaultColor = "Silver"
case "iPhone Duo": canvas = CGSize(width: 1398, height: 2034); defaultColor = "Night Sky"
// opened out, landscape, for a LinkedIn post: 4:5 portrait, 1080 × 1350
case "iPhone Duo Open": canvas = CGSize(width: 1080, height: 1350); defaultColor = "Night Sky"
default: print("unknown device \(device)"); exit(1)
}
// run from the project folder, or point BEZELS at the folder of bezels
let bezelsFolder = ProcessInfo.processInfo.environment["BEZELS"] ?? "Images/Resources/Bezels"
let bezelPath = "\(bezelsFolder)/\(device) - \(args.count > 6 ? args[6] : defaultColor).png"

// MARK: - Layout
// Measured on the original 1242 × 2688 thumbnail, then scaled to the canvas.

let design = CGSize(width: 1242, height: 2688)
let s = min(canvas.width / design.width, canvas.height / design.height)
let background = NSColor(srgbRed: 244 / 255, green: 244 / 255, blue: 248 / 255, alpha: 1)
// A landscape phone leaves the top half of a portrait post to the title, so there
// the title is set larger
let t = s * (device == "iPhone Duo Open" ? 1.45 : 1)
let line1Baseline = 272 * t, line2Baseline = 457 * t
let capHeight = 115 * t   // SF Pro capitals
let xHeight = 73 * t      // New York italic lowercase
// the phone's frame fits in this box, centred: the original's side margin, and its
// top and bottom (a wider phone, like the Duo folded, then fills the height)
// (starting lower when a larger title needs the room)
let phoneTop = max(691 * s, line2Baseline + 100 * t)
let phoneBox = CGRect(x: 174 * s, y: phoneTop, width: canvas.width - 2 * 174 * s, height: 2586 * s - phoneTop)

// MARK: - Images as plain RGBA, rows from the top

struct Pixels {
    let width: Int, height: Int
    let rep: NSBitmapImageRep
    var data: UnsafeMutablePointer<UInt8> { rep.bitmapData! }
    var rowBytes: Int { rep.bytesPerRow }

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        )!
    }

    /// Draws into it, in an upright (not flipped) context.
    func draw(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * rowBytes + x * 4 + 3] }
}

func load(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else { print("cannot read \(path)"); exit(1) }
    return image
}

// MARK: - Phone: the screenshot in the bezel's opening, the bezel over it

let bezelImage = load(bezelPath)
let bezelRep = bezelImage.representations.first!
let bezel = Pixels(width: bezelRep.pixelsWide, height: bezelRep.pixelsHigh)
bezel.draw { bezelImage.draw(in: NSRect(x: 0, y: 0, width: bezel.width, height: bezel.height)) }

// The opening: every see-through pixel joined to the middle of the bezel
var inHole = [Bool](repeating: false, count: bezel.width * bezel.height)
var stack = [bezel.height / 2 * bezel.width + bezel.width / 2]
var holeMin = (x: bezel.width, y: bezel.height), holeMax = (x: 0, y: 0)
while let index = stack.popLast() {
    if inHole[index] { continue }
    let x = index % bezel.width, y = index / bezel.width
    if bezel.alpha(x, y) > 127 { continue }
    inHole[index] = true
    holeMin = (min(holeMin.x, x), min(holeMin.y, y)); holeMax = (max(holeMax.x, x), max(holeMax.y, y))
    if x > 0 { stack.append(index - 1) }
    if x < bezel.width - 1 { stack.append(index + 1) }
    if y > 0 { stack.append(index - bezel.width) }
    if y < bezel.height - 1 { stack.append(index + bezel.width) }
}
let hole = CGRect(x: holeMin.x, y: holeMin.y, width: holeMax.x - holeMin.x + 1, height: holeMax.y - holeMin.y + 1)

// The frame's outer edge, along the middle row and column
let midRow = bezel.height / 2, midColumn = bezel.width / 2
let outerLeft = (0..<bezel.width).first { bezel.alpha($0, midRow) > 127 }!
let outerRight = (0..<bezel.width).reversed().first { bezel.alpha($0, midRow) > 127 }!
let outerTop = (0..<bezel.height).first { bezel.alpha(midColumn, $0) > 127 }!
let outerBottom = (0..<bezel.height).reversed().first { bezel.alpha(midColumn, $0) > 127 }!

// Screenshot stretched over the opening, cut to its shape, bezel on top
let phone = Pixels(width: bezel.width, height: bezel.height)
let screenshot = load(args[2])
phone.draw {
    // upright context: y from the bottom
    screenshot.draw(in: NSRect(x: hole.minX, y: CGFloat(bezel.height) - hole.maxY,
                               width: hole.width, height: hole.height))
}
for y in 0..<phone.height {
    for x in 0..<phone.width where !inHole[y * phone.width + x] {
        let i = y * phone.rowBytes + x * 4
        phone.data[i] = 0; phone.data[i + 1] = 0; phone.data[i + 2] = 0; phone.data[i + 3] = 0
    }
}
phone.draw { bezelImage.draw(in: NSRect(x: 0, y: 0, width: bezel.width, height: bezel.height)) }

// MARK: - Canvas

let out = Pixels(width: Int(canvas.width), height: Int(canvas.height))
out.draw {
    background.setFill()
    NSRect(origin: .zero, size: canvas).fill()

    // flipped from here, so y grows downwards like the measurements
    let cg = NSGraphicsContext.current!.cgContext
    cg.translateBy(x: 0, y: canvas.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Title: SF Pro sized by its capitals, New York italic by its lowercase
    let sans = NSFont(name: "SFProDisplay-Regular", size: 100)!
    let serif = NSFont(name: "NewYorkLarge-SemiboldItalic", size: 100)!
    let sansFont = NSFont(name: "SFProDisplay-Regular", size: capHeight / (sans.capHeight / 100))!
    let serifFont = NSFont(name: "NewYorkLarge-SemiboldItalic", size: xHeight / (serif.xHeight / 100))!

    func drawLine(_ markup: String, baseline: CGFloat) {
        let line = NSMutableAttributedString()
        for (index, part) in markup.components(separatedBy: "*").enumerated() where !part.isEmpty {
            line.append(NSAttributedString(string: part, attributes: [
                .font: index % 2 == 1 ? serifFont : sansFont,
                .foregroundColor: NSColor.black
            ]))
        }
        let ink = line.boundingRect(with: .zero, options: [.usesDeviceMetrics])
        let ascender = max(sansFont.ascender, serifFont.ascender)
        // a flipped context draws a line from the top of its box
        line.draw(at: NSPoint(x: canvas.width / 2 - ink.midX, y: baseline - ascender))
    }
    drawLine(args[4], baseline: line1Baseline)
    drawLine(args[5], baseline: line2Baseline)

    // Phone: its frame fitted in the box, centred, from the top of the box
    let frameWidth = CGFloat(outerRight - outerLeft + 1), frameHeight = CGFloat(outerBottom - outerTop + 1)
    let scale = min(phoneBox.width / frameWidth, phoneBox.height / frameHeight)
    let frameX = phoneBox.midX - frameWidth * scale / 2
    // a phone shorter than the box, like the Duo opened out, sits in the middle of
    // the space below the title
    let titleBottom = line2Baseline + 40 * t
    let frameY = frameHeight * scale < phoneBox.height - 1
        ? (titleBottom + canvas.height - frameHeight * scale) / 2
        : phoneBox.minY
    let rect = NSRect(x: frameX - CGFloat(outerLeft) * scale, y: frameY - CGFloat(outerTop) * scale,
                      width: CGFloat(phone.width) * scale, height: CGFloat(phone.height) * scale)
    phone.rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

try! out.rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("Saved \(args[3])")
