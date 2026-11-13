// Remi uygulama ikonu: Remi moru zemin, beyaz kalın "r", mercan ping noktası. 1024×1024, alfasız PNG.
// Çalıştırma: swift tools/make_icon.swift Remi/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics

let size = 1024.0
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

ctx.setFillColor(color(0x2A1F7A))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Logo 48 birimlik ızgarada çizilir; ikonda ortalanmış ve %70 boyutunda.
let s = size * 0.7 / 48
let ox = (size - 48 * s) / 2, oy = (size - 48 * s) / 2
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: size - (oy + y * s)) } // y yukarı

ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineWidth(7 * s)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let path = CGMutablePath()
path.move(to: p(15, 37))
path.addLine(to: p(15, 23))
path.addArc(center: p(25, 23), radius: 10 * s, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
path.addLine(to: p(26, 13))
ctx.addPath(path)
ctx.strokePath()

ctx.setFillColor(color(0xFF6B4A))
let c = p(35, 13), r = 5.5 * s
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("İkon: \(out.path)")
