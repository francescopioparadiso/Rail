// The App Store's header (3840 × 1646) and search-results (3840 × 2560) images: a grid
// of grey travel symbols with the features written over it in red, and the app icon
// in the last cell. Saved in Images/Banners.
//
// swift scripts/banners.swift        (run from the project folder)
import AppKit

// MARK: - Look, measured on the originals

let background = NSColor(srgbRed: 244 / 255, green: 244 / 255, blue: 248 / 255, alpha: 1)
let grey = NSColor(srgbRed: 218 / 255, green: 218 / 255, blue: 219 / 255, alpha: 1)
let red = NSColor(srgbRed: 255 / 255, green: 81 / 255, blue: 76 / 255, alpha: 1)
let columns = 13, columnStep: CGFloat = 287.4, rowStep: CGFloat = 200
let symbolSize: CGFloat = 108         // grey symbols
let textSize: CGFloat = 129           // red labels, SF Pro Medium
let iconGap: CGFloat = 45             // between a label's symbol and its text
let appIconSize: CGFloat = 151

/// The grey symbols, in the order they fill the grid, left to right, row by row.
let symbols = [
    "airplane", "ferry", "car", "figure.walk", "map", "location", "building.2",
    "globe.europe.africa", "mountain.2", "bicycle", "ticket", "suitcase.rolling",
    "binoculars", "road.lanes", "fuelpump", "train.side.front.car", "tram", "bus"
]

/// A feature written over the grid: on `row`, across columns `from`…`to`.
struct Label { let row: Int, from: Int, to: Int, symbol: String, text: String }

let notifications = ("bell.badge.fill", "Notifications")
let mail = ("envelope.fill", "Mail fetching")
let live = ("figure.run", "Live Activities")
let timetables = ("tablecells", "Timetables")
let search = ("location.magnifyingglass", "Intelligent search")
let passes = ("ticket.fill", "Passes")
let tracking = ("antenna.radiowaves.left.and.right", "Live tracking")
let widgets = ("square.grid.2x2.fill", "Widgets")

func label(_ row: Int, _ from: Int, _ to: Int, _ feature: (String, String)) -> Label {
    Label(row: row, from: from, to: to, symbol: feature.0, text: feature.1)
}

let images: [(name: String, size: CGSize, rows: Int, labels: [Label])] = [
    // the six that matter most
    ("header", CGSize(width: 3840, height: 1646), 8, [
        label(0, 1, 3, notifications), label(1, 8, 11, tracking), label(2, 2, 5, live),
        label(3, 9, 11, timetables), label(5, 4, 7, search), label(7, 1, 2, passes)
    ]),
    // taller, so two more, zigzagging down
    ("search_results", CGSize(width: 3840, height: 2560), 12, [
        label(0, 1, 3, notifications), label(1, 8, 11, tracking), label(3, 2, 5, live),
        label(4, 8, 11, mail), label(6, 4, 7, search), label(7, 10, 12, timetables),
        label(9, 1, 3, widgets), label(10, 7, 9, passes)
    ])
]

// MARK: - App icon, rendered from Rail.icon

let iconURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rail-app-icon.png")
let ictool = Process()
ictool.executableURL = URL(fileURLWithPath:
    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")
ictool.arguments = ["Rail/Rail.icon", "--export-image", "--output-file", iconURL.path,
                    "--platform", "iOS", "--rendition", "Default",
                    "--width", "1024", "--height", "1024", "--scale", "1"]
ictool.standardOutput = FileHandle.nullDevice
ictool.standardError = FileHandle.nullDevice
try ictool.run()
ictool.waitUntilExit()
guard let appIcon = NSImage(contentsOf: iconURL) else { print("could not render Rail/Rail.icon"); exit(1) }

// MARK: - Drawing

/// `colors` paints the symbol's layers in order.
func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, colors: [NSColor]) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
}

let outFolder = "Images/Banners"
try FileManager.default.createDirectory(atPath: outFolder, withIntermediateDirectories: true)

for image in images {
    let size = image.size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let base = NSGraphicsContext(bitmapImageRep: rep)!
    // flipped: rows counted from the top
    base.cgContext.translateBy(x: 0, y: size.height)
    base.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: base.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .high

    background.setFill()
    NSRect(origin: .zero, size: size).fill()

    // the grid, centred on the image
    let left = (size.width - CGFloat(columns - 1) * columnStep) / 2
    let top = (size.height - CGFloat(image.rows - 1) * rowStep) / 2
    func center(_ row: Int, _ column: Int) -> CGPoint {
        CGPoint(x: left + CGFloat(column) * columnStep, y: top + CGFloat(row) * rowStep)
    }
    func draw(_ picture: NSImage, centeredAt point: CGPoint) {
        picture.draw(in: NSRect(x: point.x - picture.size.width / 2, y: point.y - picture.size.height / 2,
                                width: picture.size.width, height: picture.size.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // Grey symbols in every cell not taken by a label or the app icon
    var next = 0
    for row in 0..<image.rows {
        for column in 0..<columns {
            let taken = image.labels.contains { $0.row == row && (column >= $0.from && column <= $0.to) }
            let isIcon = row == image.rows - 1 && column == columns - 1
            guard !taken, !isIcon else { continue }
            draw(symbol(symbols[next % symbols.count], size: symbolSize, weight: .regular, colors: [grey]),
                 centeredAt: center(row, column))
            next += 1
        }
    }

    // Red labels, centred across their cells, with a soft red glow
    let font = NSFont(name: "SFProDisplay-Medium", size: textSize)!
    for item in image.labels {
        let glyph = symbol(item.symbol, size: textSize * 0.95, weight: .medium, colors: [red])
        let text = NSAttributedString(string: item.text, attributes: [.font: font, .foregroundColor: red])
        let textWidth = text.size().width
        let width = glyph.size.width + iconGap + textWidth
        let span = (center(item.row, item.from).x - columnStep / 2, center(item.row, item.to).x + columnStep / 2)
        let x = (span.0 + span.1) / 2 - width / 2
        let y = center(item.row, 0).y

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = red.withAlphaComponent(0.35)
        glow.shadowBlurRadius = 40
        glow.shadowOffset = .zero
        glow.set()
        draw(glyph, centeredAt: CGPoint(x: x + glyph.size.width / 2, y: y))
        // the capitals centred on the row
        text.draw(at: NSPoint(x: x + glyph.size.width + iconGap,
                              y: y - font.ascender + font.capHeight / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    // The app icon, in the last cell, with a faint shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
    shadow.shadowBlurRadius = 16
    shadow.shadowOffset = NSSize(width: 0, height: -4)
    shadow.set()
    let iconCenter = center(image.rows - 1, columns - 1)
    appIcon.draw(in: NSRect(x: iconCenter.x - appIconSize / 2, y: iconCenter.y - appIconSize / 2,
                            width: appIconSize, height: appIconSize),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    let path = "\(outFolder)/\(image.name).png"
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Saved \(path)")
}
