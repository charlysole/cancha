// Dibuja el icono de Cancha (1024x1024 PNG): una cancha vista de arriba con la pelota en el medio.
// Es dibujo propio: no usa nada del juego.
//
// uso: swift herramientas/icono.swift <salida.png>
import AppKit

let lado: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(lado), height: Int(lado), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Cuerpo del icono según la grilla de macOS: 824x824 centrado, esquinas de ~185.
let cuerpo = CGRect(x: 100, y: 100, width: 824, height: 824)
let forma = CGPath(roundedRect: cuerpo, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Sombra suave debajo
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
ctx.addPath(forma)
ctx.setFillColor(color(46, 140, 64))
ctx.fillPath()
ctx.restoreGState()

// Pasto a franjas
ctx.saveGState()
ctx.addPath(forma)
ctx.clip()
let franjas = 8
for i in 0..<franjas {
    let ancho = cuerpo.width / CGFloat(franjas)
    ctx.setFillColor(i % 2 == 0 ? color(52, 156, 72) : color(44, 138, 62))
    ctx.fill(CGRect(x: cuerpo.minX + CGFloat(i) * ancho, y: cuerpo.minY, width: ancho, height: cuerpo.height))
}
// Brillo arriba
let brillo = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [color(255, 255, 255, 0.18), color(255, 255, 255, 0)] as CFArray,
                        locations: [0, 1])!
ctx.drawLinearGradient(brillo, start: CGPoint(x: 0, y: cuerpo.maxY), end: CGPoint(x: 0, y: cuerpo.midY), options: [])

// Líneas de cal
let linea: CGFloat = 16
ctx.setStrokeColor(color(255, 255, 255, 0.92))
ctx.setLineWidth(linea)
let campo = cuerpo.insetBy(dx: 92, dy: 92)
ctx.stroke(campo)
ctx.move(to: CGPoint(x: campo.midX, y: campo.minY))
ctx.addLine(to: CGPoint(x: campo.midX, y: campo.maxY))
ctx.strokePath()
ctx.strokeEllipse(in: CGRect(x: campo.midX - 150, y: campo.midY - 150, width: 300, height: 300))
// Áreas
let area = CGSize(width: 110, height: 300)
ctx.stroke(CGRect(x: campo.minX, y: campo.midY - area.height / 2, width: area.width, height: area.height))
ctx.stroke(CGRect(x: campo.maxX - area.width, y: campo.midY - area.height / 2, width: area.width, height: area.height))
ctx.restoreGState()

// Pelota en el centro
let radio: CGFloat = 96
let centro = CGPoint(x: campo.midX, y: campo.midY)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 10, height: -14), blur: 18, color: color(0, 0, 0, 0.4))
ctx.setFillColor(color(250, 250, 250))
ctx.fillEllipse(in: CGRect(x: centro.x - radio, y: centro.y - radio, width: radio * 2, height: radio * 2))
ctx.restoreGState()

// Pentágono negro en el medio y costuras hacia el borde
func punto(_ r: CGFloat, _ angulo: CGFloat) -> CGPoint {
    CGPoint(x: centro.x + r * cos(angulo), y: centro.y + r * sin(angulo))
}
let pentagono = CGMutablePath()
for k in 0..<5 {
    let p = punto(radio * 0.36, .pi / 2 + CGFloat(k) * 2 * .pi / 5)
    k == 0 ? pentagono.move(to: p) : pentagono.addLine(to: p)
}
pentagono.closeSubpath()
ctx.addPath(pentagono)
ctx.setFillColor(color(30, 30, 34))
ctx.fillPath()
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: centro.x - radio, y: centro.y - radio, width: radio * 2, height: radio * 2))
ctx.clip()
ctx.setStrokeColor(color(30, 30, 34))
ctx.setLineWidth(7)
for k in 0..<5 {
    let a = .pi / 2 + CGFloat(k) * 2 * .pi / 5
    ctx.move(to: punto(radio * 0.36, a))
    ctx.addLine(to: punto(radio * 0.78, a))
    ctx.strokePath()
    // Medio pentágono asomando en el borde
    let borde = CGMutablePath()
    for j in 0..<5 {
        let c = punto(radio * 1.02, a)
        let p = CGPoint(x: c.x + radio * 0.3 * cos(a + .pi + CGFloat(j) * 2 * .pi / 5),
                        y: c.y + radio * 0.3 * sin(a + .pi + CGFloat(j) * 2 * .pi / 5))
        j == 0 ? borde.move(to: p) : borde.addLine(to: p)
    }
    borde.closeSubpath()
    ctx.addPath(borde)
    ctx.setFillColor(color(30, 30, 34))
    ctx.fillPath()
}
ctx.restoreGState()
// Contorno de la pelota
ctx.setStrokeColor(color(30, 30, 34, 0.55))
ctx.setLineWidth(4)
ctx.strokeEllipse(in: CGRect(x: centro.x - radio, y: centro.y - radio, width: radio * 2, height: radio * 2))

let imagen = ctx.makeImage()!
let datos = NSBitmapImageRep(cgImage: imagen).representation(using: .png, properties: [:])!
try! datos.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
