// Génère AppIcon.icns à partir de flan.svg (grandes tailles) et flan-small.svg (16 à 64 px).
//
// Exemple d'appel (depuis la racine du repo) :
//   swiftc -O Resources/Icon/make_icon.swift -o .build/make_icon && .build/make_icon Resources/Icon
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
guard let big = NSImage(contentsOf: dir.appendingPathComponent("flan.svg")),
      let small = NSImage(contentsOf: dir.appendingPathComponent("flan-small.svg"))
else {
    print("SVG illisible")
    exit(1)
}

/// Dessine l'icône à la taille demandée (en pixels), avec l'ombre portée du gabarit macOS.
func render(_ pixels: Int) -> Data? {
    let source = pixels <= 64 ? small : big
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowBlurRadius = 22 * scale
    shadow.set()
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    guard let png = render(px) else { print("Échec \(name)"); exit(1) }
    try png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("Iconset prêt : \(iconset.path)")
