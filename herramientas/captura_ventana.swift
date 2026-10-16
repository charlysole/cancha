// Uso: captura_ventana <titulo-exacto> <salida.png> [dueño-exacto]
// Captura sola la ventana cuyo título es exactamente ese (y, si se indica, cuyo proceso dueño también).
// Coincidencia exacta a propósito: con "contiene" llegó a capturar documentos personales del usuario.
// Título "*" = cualquier título, pero entonces el dueño exacto es obligatorio.
import CoreGraphics
import Foundation
let args = CommandLine.arguments
let needle = args[1]
let owner = args.count > 3 ? args[3] : nil
if needle == "*" && owner == nil { print("con título * hace falta el dueño"); exit(2) }
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String:Any]]
var best: (Int, Double)? = nil
for w in l {
    let o = w["kCGWindowOwnerName"] as? String ?? ""
    let t = w["kCGWindowName"] as? String ?? ""
    guard t == needle || needle == "*", owner == nil || o == owner! else { continue }
    let b = w["kCGWindowBounds"] as! [String:Double]
    let area = b["Width"]! * b["Height"]!
    if area > (best?.1 ?? 10000) { best = (w["kCGWindowNumber"] as! Int, area) }
}
guard let (id, _) = best else { print("sin ventana"); exit(1) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", String(id), args[2]]; try! p.run(); p.waitUntilExit()
print("ventana \(id) capturada")
