// Cancha — ventana de inicio de un launcher para jugar PES6 en Mac (no afiliado a Konami).
//
//   Jugar            juego normal (sin servidor propio)
//   Hostear partido  levanta el servidor (Python + fiveserver dentro de la app), abre los puertos del
//                    router por UPnP, muestra la IP para pasarle al amigo y abre el juego conectado a él
//   Unirse           abre el juego conectado al servidor de otro (IP que escribe el usuario)
//
// El juego en sí lo arranca Contents/Resources/lanzar_juego.sh (Wine). Esta app prepara antes:
// carpeta del juego, serial, pantalla completa/resolución (settings.dat) y Rosetta.

import AppKit
import CoreGraphics

let soporte = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Cancha")

/// Hasta la versión 1.3 la app se llamaba "PES6 Mac": sus datos (serial, prefijo de Wine, servidor) se mudan
/// una sola vez a la carpeta nueva.
func mudarDatosViejos() {
    let viejo = soporte.deletingLastPathComponent().appendingPathComponent("PES6 Mac")
    let fm = FileManager.default
    guard fm.fileExists(atPath: viejo.path), !fm.fileExists(atPath: soporte.path) else { return }
    try? fm.moveItem(at: viejo, to: soporte)
}
let recursos = Bundle.main.resourceURL!

func leer(_ nombre: String) -> String? {
    (try? String(contentsOf: soporte.appendingPathComponent(nombre), encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func guardar(_ nombre: String, _ texto: String) {
    try? FileManager.default.createDirectory(at: soporte, withIntermediateDirectories: true)
    try? texto.write(to: soporte.appendingPathComponent(nombre), atomically: true, encoding: .utf8)
}

func alerta(_ titulo: String, _ texto: String, estilo: NSAlert.Style = .warning) {
    let a = NSAlert()
    a.messageText = titulo
    a.informativeText = texto
    a.alertStyle = estilo
    a.runModal()
}

// MARK: - Carpeta del juego

func esCarpetaJuego(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appendingPathComponent("PES6.exe").path)
}

/// Al lado de la app, la guardada antes, o la que elija el usuario.
func buscarJuego() -> URL? {
    let junto = Bundle.main.bundleURL.deletingLastPathComponent()
    if let hijos = try? FileManager.default.contentsOfDirectory(
        at: junto, includingPropertiesForKeys: nil) {
        for d in hijos.sorted(by: { $0.path < $1.path }) where esCarpetaJuego(d) { return d }
    }
    if let g = leer("carpeta_juego.txt"), esCarpetaJuego(URL(fileURLWithPath: g)) {
        return URL(fileURLWithPath: g)
    }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Elegí la carpeta de PES6 (la que tiene PES6.exe)"
    guard panel.runModal() == .OK, let u = panel.url, esCarpetaJuego(u) else { return nil }
    return u
}

// MARK: - Ajustes del juego (My Document/settings.dat)
//
// Formato descubierto comparando el archivo antes y después de usar settings.exe:
//   0x02      suma de verificación: (suma de los bytes desde 0x04) & 0xFF
//   0x04-0x05 ancho, 0x06-0x07 alto (little endian)
//   0x08      1 = pantalla completa, 0 = ventana

func resolucionPantalla() -> (Int, Int) {
    if let modo = CGDisplayCopyDisplayMode(CGMainDisplayID()) {
        return (modo.width, modo.height)
    }
    return (1280, 720)
}

// El modo "pantalla completa" real del juego no sirve en Mac: Wine no puede cambiar el modo de video
// (ChangeDisplaySettings -2) y el juego cae a 640x480. En su lugar el juego corre "en ventana" y el
// módulo dxtools del kitserver (opciones dx.window.* de kitserver/kload.cfg) hace esa ventana sin bordes
// y del tamaño exacto de la pantalla; el driver de Mac de Wine la muestra como pantalla completa.

// Resolución interna (internal.resolution.* de kload.cfg): el juego dibuja a esa resolución y la escala a
// la ventana. Más alta = más nítido, pero cuesta GPU. Como en el port de SoF2 (donde un M1 base caía a
// pocos FPS), se elige según la GPU: núcleos de GPU de Apple Silicon (IOKit AGXAccelerator gpu-core-count).
//   baja  : Intel o <= 8 núcleos (M1/M2 base de 7-8)  -> la de la pantalla, sin extra
//   media : 9-15 núcleos (M2/M3/M4 base de 10, M1 Pro de 14) -> 1440p
//   alta  : >= 16 núcleos (Pro/Max)                   -> 2160p (4K)
enum Calidad: String, CaseIterable { case automatica, baja, media, alta }

func nucleosGPU() -> Int {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    p.arguments = ["-rc", "AGXAccelerator", "-d1"]
    let tubo = Pipe()
    p.standardOutput = tubo
    guard (try? p.run()) != nil else { return 0 }
    let texto = String(data: tubo.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    guard let r = texto.range(of: "\"gpu-core-count\" = ") else { return 0 }   // Intel: no hay
    return Int(texto[r.upperBound...].prefix { $0.isNumber }) ?? 0
}

func calidadEfectiva() -> Calidad {
    let elegida = Calidad(rawValue: leer("calidad.txt") ?? "") ?? .automatica
    guard elegida == .automatica else { return elegida }
    let n = nucleosGPU()
    return n >= 16 ? .alta : (n >= 9 ? .media : .baja)
}

/// Resolución interna para una ventana de ancho x alto (nil = la misma de la ventana).
func resolucionInterna(_ ancho: Int, _ alto: Int) -> (Int, Int)? {
    let objetivo: Int
    switch calidadEfectiva() {
    case .alta: objetivo = 2160
    case .media: objetivo = 1440
    default: return nil
    }
    guard objetivo > alto else { return nil }
    let w = Int((Double(objetivo) * Double(ancho) / Double(alto)).rounded()) & ~1
    return (w, objetivo)
}

// Marcas con el nombre viejo de la app: así se reconocen los bloques que escribieron las versiones anteriores.
let inicioBloque = "# --- PES6 Mac: pantalla (lo reescribe la app) ---"
let finBloque = "# --- fin PES6 Mac ---"

func escribirAjustes(juego: URL, pantallaCompleta: Bool) {
    let (ancho, alto) = pantallaCompleta ? resolucionPantalla() : (1280, 720)

    let url = juego.appendingPathComponent("My Document/settings.dat")
    if var d = try? Data(contentsOf: url), d.count > 16 {
        d[4] = UInt8(ancho & 0xFF); d[5] = UInt8(ancho >> 8)
        d[6] = UInt8(alto & 0xFF); d[7] = UInt8(alto >> 8)
        d[8] = 0                                    // siempre "ventana" (ver arriba)
        d[2] = UInt8(d[4...].reduce(0) { ($0 + Int($1)) & 0xFF })
        try? d.write(to: url)
    }

    let cfg = juego.appendingPathComponent("kitserver/kload.cfg")
    guard var texto = try? String(contentsOf: cfg, encoding: .utf8) else { return }
    let nl = texto.contains("\r\n") ? "\r\n" : "\n"      // el archivo viene de Windows (CRLF)
    if let i = texto.range(of: nl + inicioBloque),
       let f = texto.range(of: finBloque + nl, range: i.upperBound..<texto.endIndex) {
        texto.removeSubrange(i.lowerBound..<f.upperBound)
    }
    var bloque = [inicioBloque]
    if pantallaCompleta {
        bloque += ["dx.window.x = 0", "dx.window.y = 0",
                   "dx.window.width = \(ancho)", "dx.window.height = \(alto)",
                   "dx.window.style = 0x90000000", "dx.window.exstyle = 0x0"]   // WS_POPUP | WS_VISIBLE
    } else {
        bloque += ["dx.window.width = \(ancho)", "dx.window.height = \(alto)"]
    }
    if let (iw, ih) = resolucionInterna(ancho, alto) {
        bloque += ["internal.resolution.width = \(iw)", "internal.resolution.height = \(ih)"]
    }
    bloque.append(finBloque)
    if !texto.hasSuffix(nl) { texto += nl }
    texto += nl + bloque.joined(separator: nl) + nl
    try? texto.write(to: cfg, atomically: true, encoding: .utf8)
}

// MARK: - Rosetta (el motor de Wine es x86_64)

func necesitaRosetta() -> Bool {
    var arm: Int32 = 0
    var tam = MemoryLayout<Int32>.size
    sysctlbyname("hw.optional.arm64", &arm, &tam, nil, 0)
    guard arm == 1 else { return false }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
    p.arguments = ["-x86_64", "/usr/bin/true"]
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus != 0
}

func instalarRosetta() -> Bool {
    let a = NSAlert()
    a.messageText = "Hace falta Rosetta"
    a.informativeText = "PES6 corre con un componente para Mac Intel. macOS lo traduce con Rosetta, que no está instalado. ¿Instalarlo ahora? (te va a pedir la contraseña)"
    a.addButton(withTitle: "Instalar")
    a.addButton(withTitle: "Cancelar")
    guard a.runModal() == .alertFirstButtonReturn else { return false }
    let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
    return !necesitaRosetta()
}

// MARK: - Serial

func pedirSerial(obligatorio: Bool) -> Bool {
    if let s = leer("serial.txt"), s.count == 20 { return true }
    let a = NSAlert()
    a.messageText = "Código de registro de PES6"
    a.informativeText = "El juego necesita el código de registro de tu copia de PES6: el que pusiste al instalarlo (20 letras y números, con o sin guiones). Se guarda en esta Mac y no se manda a ningún lado salvo al juego."
    let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    campo.placeholderString = "XXXX-XXXX-XXXX-XXXX-XXXX"
    a.accessoryView = campo
    a.addButton(withTitle: "Guardar")
    a.addButton(withTitle: obligatorio ? "Cancelar" : "Ahora no")
    a.window.initialFirstResponder = campo
    guard a.runModal() == .alertFirstButtonReturn else { return !obligatorio }
    let limpio = campo.stringValue.uppercased().filter { $0.isLetter || $0.isNumber }
    guard limpio.count == 20 else {
        alerta("Código inválido", "Tiene que tener 20 letras y números.")
        return pedirSerial(obligatorio: obligatorio)
    }
    guardar("serial.txt", limpio)
    return true
}

// MARK: - Cartel "Iniciando el juego…"
//
// Wine tarda en abrir el juego (bastante la primera vez): mientras, un cartel en el medio de la
// pantalla para que se sepa que algo está pasando. Se va cuando aparece la ventana del juego.

final class Cartel {
    let panel: NSPanel
    let texto: NSTextField
    let detalle: NSTextField
    let rueda = NSProgressIndicator()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let fondo = NSVisualEffectView()
        fondo.material = .hudWindow
        fondo.blendingMode = .behindWindow
        fondo.state = .active
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = 16
        fondo.layer?.masksToBounds = true
        panel.contentView = fondo

        rueda.style = .spinning
        rueda.controlSize = .regular
        texto = NSTextField(labelWithString: "")
        texto.font = .systemFont(ofSize: 20, weight: .semibold)
        texto.alignment = .center
        detalle = NSTextField(labelWithString: "")
        detalle.font = .systemFont(ofSize: 12)
        detalle.textColor = .secondaryLabelColor
        detalle.alignment = .center
        detalle.lineBreakMode = .byWordWrapping
        detalle.preferredMaxLayoutWidth = 330

        let pila = NSStackView(views: [rueda, texto, detalle])
        pila.orientation = .vertical
        pila.alignment = .centerX
        pila.spacing = 10
        pila.translatesAutoresizingMaskIntoConstraints = false
        fondo.addSubview(pila)
        NSLayoutConstraint.activate([
            pila.centerXAnchor.constraint(equalTo: fondo.centerXAnchor),
            pila.centerYAnchor.constraint(equalTo: fondo.centerYAnchor),
            pila.widthAnchor.constraint(lessThanOrEqualTo: fondo.widthAnchor, constant: -40),
        ])
    }

    func mostrar(_ titulo: String, _ sub: String) {
        texto.stringValue = titulo
        detalle.stringValue = sub
        if !panel.isVisible {
            let pantalla = (NSScreen.main ?? NSScreen.screens[0]).frame
            panel.setFrameOrigin(NSPoint(x: pantalla.midX - panel.frame.width / 2,
                                         y: pantalla.midY - panel.frame.height / 2))
            panel.orderFrontRegardless()
        }
        rueda.startAnimation(nil)
    }

    func ocultar() {
        rueda.stopAnimation(nil)
        panel.orderOut(nil)
    }
}

/// El proceso de Wine del exe dado, cuando ya tiene una ventana grande en pantalla.
/// (Dueño y tamaño de la ventana: no hace falta el permiso de grabación de pantalla, el título sí.)
func procesoConVentana(de exe: String) -> pid_t? {
    guard let ventanas = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
    for v in ventanas {
        guard let dueno = v[kCGWindowOwnerName as String] as? String,
              dueno.caseInsensitiveCompare(exe) == .orderedSame,
              let pid = v[kCGWindowOwnerPID as String] as? pid_t,
              let caja = v[kCGWindowBounds as String] as? [String: CGFloat],
              (caja["Width"] ?? 0) >= 300, (caja["Height"] ?? 0) >= 200 else { continue }
        return pid
    }
    return nil
}

// MARK: - Ventana

final class Controlador: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var ventana: NSWindow!
    var estado: NSTextField!
    var direccion: NSTextField!
    var copiar: NSButton!
    var campoIP: NSTextField!
    var completa: NSButton!
    var botones: [NSButton] = []
    var juego: URL!
    var servidor: Process?
    var partida: Process?
    let cartel = Cartel()
    var esperaVentana: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        mudarDatosViejos()
        armarMenu()
        armarVentana()
        NSApp.activate(ignoringOtherApps: true)

        if Bundle.main.bundlePath.contains("/AppTranslocation/") ||
            Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            alerta("Copiá Cancha a tu Mac",
                   "Arrastrá la carpeta «Cancha» del disco a Aplicaciones y abrí la app desde ahí. Desde el disco no se puede jugar porque el juego necesita guardar datos en su carpeta.")
            NSApp.terminate(nil)
            return
        }
        guard let j = buscarJuego() else { NSApp.terminate(nil); return }
        juego = j
        guardar("carpeta_juego.txt", j.path)
        if necesitaRosetta() && !instalarRosetta() { NSApp.terminate(nil); return }
    }

    func armarMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let sub = NSMenu()
        sub.addItem(withTitle: "Cambiar código de registro…", action: #selector(cambiarSerial), keyEquivalent: "")
        sub.addItem(withTitle: "Abrir carpeta del juego", action: #selector(abrirCarpeta), keyEquivalent: "")
        sub.addItem(.separator())
        let calidad = NSMenuItem(title: "Calidad gráfica", action: nil, keyEquivalent: "")
        let opciones = NSMenu()
        let actual = Calidad(rawValue: leer("calidad.txt") ?? "") ?? .automatica
        let nombres: [Calidad: String] = [
            .automatica: "Automática (según tu Mac)", .baja: "Baja (resolución de pantalla)",
            .media: "Media (1440p)", .alta: "Alta (4K)"]
        for c in Calidad.allCases {
            let it = NSMenuItem(title: nombres[c]!, action: #selector(elegirCalidad(_:)), keyEquivalent: "")
            it.representedObject = c.rawValue
            it.state = c == actual ? .on : .off
            opciones.addItem(it)
        }
        calidad.submenu = opciones
        sub.addItem(calidad)
        sub.addItem(.separator())
        sub.addItem(withTitle: "Salir de Cancha", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = sub
        NSApp.mainMenu = menu
    }

    func etiqueta(_ texto: String, _ tam: CGFloat, _ peso: NSFont.Weight = .regular) -> NSTextField {
        let t = NSTextField(labelWithString: texto)
        t.font = .systemFont(ofSize: tam, weight: peso)
        return t
    }

    func boton(_ titulo: String, _ accion: Selector, principal: Bool = false) -> NSButton {
        let b = NSButton(title: titulo, target: self, action: accion)
        b.bezelStyle = .rounded
        b.controlSize = .large
        if principal { b.keyEquivalent = "\r" }
        botones.append(b)
        return b
    }

    func armarVentana() {
        ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                           styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        ventana.title = "Cancha"
        ventana.delegate = self

        let titulo = etiqueta("Cancha", 26, .bold)
        let sub = etiqueta("Para jugar PES6 en Mac, solo y online con amigos", 13)
        sub.textColor = .secondaryLabelColor

        let jugar = boton("Jugar", #selector(jugar), principal: true)
        let hostear = boton("Hostear partido", #selector(hostear))
        campoIP = NSTextField(string: leer("ultimo_host.txt") ??
            ((try? String(contentsOf: recursos.appendingPathComponent("servidor_predeterminado.txt"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
        campoIP.placeholderString = "IP del que hostea"
        campoIP.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let unirse = boton("Unirse", #selector(unirse))
        let filaUnirse = NSStackView(views: [campoIP, unirse])

        completa = NSButton(checkboxWithTitle: "Pantalla completa", target: self, action: #selector(cambioPantalla))
        completa.state = leer("ventana.txt") == "1" ? .off : .on
        let ajustes = boton("Controles…", #selector(controles))
        ajustes.controlSize = .regular
        let filaOpciones = NSStackView(views: [completa, ajustes])
        filaOpciones.spacing = 20

        estado = etiqueta("", 12)
        estado.textColor = .secondaryLabelColor
        estado.lineBreakMode = .byWordWrapping
        estado.preferredMaxLayoutWidth = 400
        direccion = etiqueta("", 22, .semibold)
        direccion.isSelectable = true
        copiar = NSButton(title: "Copiar", target: self, action: #selector(copiarDireccion))
        copiar.isHidden = true
        let filaDireccion = NSStackView(views: [direccion, copiar])

        let pila = NSStackView(views: [titulo, sub, jugar, hostear, filaUnirse, filaOpciones, filaDireccion, estado])
        pila.orientation = .vertical
        pila.alignment = .centerX
        pila.spacing = 12
        pila.setCustomSpacing(24, after: sub)
        pila.setCustomSpacing(20, after: filaOpciones)
        for b in [jugar, hostear] { b.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        pila.translatesAutoresizingMaskIntoConstraints = false
        ventana.contentView!.addSubview(pila)
        NSLayoutConstraint.activate([
            pila.centerXAnchor.constraint(equalTo: ventana.contentView!.centerXAnchor),
            pila.topAnchor.constraint(equalTo: ventana.contentView!.topAnchor, constant: 24),
        ])
        ventana.center()
        ventana.makeKeyAndOrderFront(nil)
    }

    func ocupado(_ si: Bool) {
        for b in botones { b.isEnabled = !si }
        campoIP.isEnabled = !si
    }

    // MARK: acciones

    @objc func elegirCalidad(_ item: NSMenuItem) {
        guardar("calidad.txt", item.representedObject as! String)
        for it in item.menu!.items { it.state = it === item ? .on : .off }
    }

    @objc func cambioPantalla() { guardar("ventana.txt", completa.state == .on ? "0" : "1") }
    @objc func cambiarSerial() {
        try? FileManager.default.removeItem(at: soporte.appendingPathComponent("serial.txt"))
        _ = pedirSerial(obligatorio: false)
    }
    @objc func abrirCarpeta() { if let j = juego { NSWorkspace.shared.open(j) } }
    @objc func copiarDireccion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(direccion.stringValue, forType: .string)
    }

    @objc func jugar() {
        guard pedirSerial(obligatorio: true) else { return }
        lanzar(servidor: "")
    }

    @objc func controles() {
        guard pedirSerial(obligatorio: true) else { return }
        lanzar(servidor: "", exe: "settings.exe")
    }

    @objc func unirse() {
        let ip = campoIP.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty, ip.count <= 26, !ip.contains(" ") else {
            alerta("Falta la dirección", "Escribí la IP que te pasó el que hostea el partido.")
            return
        }
        guard pedirSerial(obligatorio: true) else { return }
        guardar("ultimo_host.txt", ip)
        lanzar(servidor: ip)
    }

    @objc func hostear() {
        guard pedirSerial(obligatorio: true) else { return }
        ocupado(true)
        estado.stringValue = "Levantando el servidor y abriendo puertos en el router…"
        cartel.mostrar("Preparando el partido…", "Levantando el servidor y abriendo los puertos del router.")
        let p = Process()
        p.executableURL = recursos.appendingPathComponent("python/bin/python3")
        p.arguments = ["-u", recursos.appendingPathComponent("servidor/servidor_pes6.py").path,
                       "--datos", soporte.appendingPathComponent("servidor").path]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = tubo
        var ip = ""
        var upnp = true
        var listo = false
        tubo.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let texto = String(data: h.availableData, encoding: .utf8), !texto.isEmpty else { return }
            for linea in texto.split(separator: "\n") {
                if linea.contains("UPnP: no") || linea.contains("UPnP: no pude") { upnp = false }
                if linea.contains("| UPnP: no") { upnp = false }
                if let r = linea.range(of: "usar la dirección ") { ip = String(linea[r.upperBound...]) }
                if linea.contains("LISTO") && !listo {
                    listo = true
                    DispatchQueue.main.async { self?.servidorListo(ip: ip, upnp: upnp) }
                }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if !listo {
                    self.cartel.ocultar()
                    self.ocupado(false)
                    self.estado.stringValue = "El servidor no pudo arrancar. Mirá ~/Library/Application Support/Cancha/servidor/servidor.log"
                }
                self.servidor = nil
            }
        }
        do { try p.run() } catch {
            cartel.ocultar()
            ocupado(false)
            estado.stringValue = "No se pudo iniciar el servidor: \(error.localizedDescription)"
            return
        }
        servidor = p
    }

    func servidorListo(ip: String, upnp: Bool) {
        direccion.stringValue = ip
        copiar.isHidden = false
        estado.stringValue = upnp
            ? "Pasale esta dirección a tu amigo: la escribe en «Unirse». El servidor queda abierto mientras el juego esté abierto."
            : "El router no aceptó abrir los puertos solo (UPnP). Para que entren de afuera, abrí a mano TCP 10881, 20200-20202 y UDP 3478-3479, 5739 hacia esta Mac."
        lanzar(servidor: "127.0.0.1")
    }

    func lanzar(servidor ip: String, exe: String = "PES6.exe") {
        ocupado(true)
        if exe == "PES6.exe" { escribirAjustes(juego: juego, pantallaCompleta: completa.state == .on) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [recursos.appendingPathComponent("lanzar_juego.sh").path]
        var env = ProcessInfo.processInfo.environment
        env["PES6_JUEGO"] = juego.path
        env["PES6_SERVIDOR"] = ip
        env["PES6_EXE"] = exe
        p.environment = env
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.juegoTerminado() }
        }
        do { try p.run() } catch {
            cartel.ocultar()
            alerta("No se pudo abrir el juego", error.localizedDescription)
            ocupado(false)
            return
        }
        partida = p
        if ip.isEmpty || ip != "127.0.0.1" { estado.stringValue = "Abriendo el juego…" }
        let primeraVez = !FileManager.default.fileExists(atPath: soporte.appendingPathComponent("prefijo/system.reg").path)
        cartel.mostrar(exe == "PES6.exe" ? "Iniciando el juego…" : "Abriendo los controles…",
                       primeraVez ? "La primera vez tarda más: se prepara el entorno de Windows (puede llevar un par de minutos)."
                                  : "Puede tardar unos segundos.")
        esperarVentana(de: exe == "PES6.exe" ? ["PES6.exe", "PES6_mac.exe"] : [exe])
    }

    /// Cuando aparece la ventana del juego: se va el cartel, la ventana de inicio se minimiza y el juego
    /// pasa al frente. Tiene que ser la app activa: si no, Wine deja la ventana en el nivel normal y la
    /// barra de menú y el Dock (si no se oculta solo) quedan dibujados encima del juego.
    func esperarVentana(de exes: [String]) {
        esperaVentana?.invalidate()
        esperaVentana = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard let pid = exes.lazy.compactMap({ procesoConVentana(de: $0) }).first else { return }
            t.invalidate()
            self.esperaVentana = nil
            self.cartel.ocultar()
            self.ventana.miniaturize(nil)
            self.traerAlFrente(pid)
        }
    }

    func traerAlFrente(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func juegoTerminado() {
        partida = nil
        esperaVentana?.invalidate()
        esperaVentana = nil
        cartel.ocultar()
        detenerServidor()
        ocupado(false)
        copiar.isHidden = true
        direccion.stringValue = ""
        estado.stringValue = ""
        ventana.deminiaturize(nil)
    }

    func detenerServidor() {
        guard let s = servidor, s.isRunning else { return }
        s.interrupt()          // SIGINT: Twisted cierra los puertos del router antes de salir
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if s.isRunning { s.terminate() } }
    }

    func applicationWillTerminate(_ n: Notification) {
        detenerServidor()
        if let s = servidor { s.waitUntilExit() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { partida == nil }

    func windowShouldClose(_ w: NSWindow) -> Bool {
        if partida != nil { w.miniaturize(nil); return false }
        return true
    }
}

let app = NSApplication.shared
let controlador = Controlador()
app.delegate = controlador
app.setActivationPolicy(.regular)
app.run()
