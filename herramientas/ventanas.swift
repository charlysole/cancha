import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String:Any]]
for w in l { let o = w["kCGWindowOwnerName"] as? String ?? ""; if o.lowercased().contains("wine") || o.lowercased().contains("pes6") { print(o, w["kCGWindowName"] ?? "", w["kCGWindowNumber"]!, w["kCGWindowBounds"]!, w["kCGWindowIsOnscreen"] ?? "") } }
