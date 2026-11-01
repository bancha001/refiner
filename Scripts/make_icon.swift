// Renders the app icon. Run: ./Scripts/make_icon.sh
import AppKit

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Rounded-square body on Apple's icon grid (824pt body inside a 1024pt canvas).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x4B3FD1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(colorsSpace: space,
                            colors: [color(0x8A6CFF), color(0x5B4BE6), color(0x2C2A86)] as CFArray,
                            locations: [0, 0.5, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 150, y: 924), end: CGPoint(x: 874, y: 100), options: [])
// Soft glow behind the sparkle.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 712, y: 745), startRadius: 0,
                       endCenter: CGPoint(x: 712, y: 745), endRadius: 330, options: [])
ctx.restoreGState()

// The page.
let page = CGRect(x: 230, y: 215, width: 500, height: 570)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x15124A, 0.4))
ctx.addPath(CGPath(roundedRect: page, cornerWidth: 52, cornerHeight: 52, transform: nil))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Rough text: wavy scribbles.
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(26)
ctx.setStrokeColor(color(0xBDB7DC))
for (y, endX) in [(CGFloat(650), CGFloat(620)), (CGFloat(552), CGFloat(560))] {
    let wave = CGMutablePath()
    wave.move(to: CGPoint(x: 300, y: y))
    var x: CGFloat = 300
    var up = true
    while x < endX {
        let next = min(x + 44, endX)
        wave.addQuadCurve(to: CGPoint(x: next, y: y), control: CGPoint(x: (x + next) / 2, y: y + (up ? 26 : -26)))
        x = next
        up.toggle()
    }
    ctx.addPath(wave)
    ctx.strokePath()
}

// Refined text: clean lines.
ctx.setFillColor(color(0x5B4BE6))
for (y, width) in [(CGFloat(430), CGFloat(360)), (CGFloat(330), CGFloat(250))] {
    ctx.addPath(CGPath(roundedRect: CGRect(x: 300, y: y - 16, width: width, height: 32),
                       cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.fillPath()
}

// Four-point sparkles.
func sparkle(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let tips = [CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + r, y: c.y),
                CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r, y: c.y)]
    let pinch = r * 0.16
    path.move(to: tips[0])
    for i in 0..<4 {
        let a = tips[i], b = tips[(i + 1) % 4]
        let mid = CGPoint(x: c.x + ((a.x - c.x) + (b.x - c.x)) / 2 * pinch / r * 1.4,
                          y: c.y + ((a.y - c.y) + (b.y - c.y)) / 2 * pinch / r * 1.4)
        path.addQuadCurve(to: b, control: mid)
    }
    path.closeSubpath()
    return path
}

let gold = CGGradient(colorsSpace: space, colors: [color(0xFFF1B0), color(0xFFC94A), color(0xFF9E2C)] as CFArray,
                      locations: [0, 0.5, 1])!
for (center, radius) in [(CGPoint(x: 712, y: 745), CGFloat(150)), (CGPoint(x: 830, y: 575), CGFloat(62))] {
    let star = sparkle(center: center, radius: radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x8A4A00, 0.45))
    ctx.addPath(star)
    ctx.setFillColor(color(0xFFC94A))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(star)
    ctx.clip()
    ctx.drawLinearGradient(gold, start: CGPoint(x: center.x - radius, y: center.y + radius),
                           end: CGPoint(x: center.x + radius, y: center.y - radius), options: [])
    ctx.restoreGState()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: output)
