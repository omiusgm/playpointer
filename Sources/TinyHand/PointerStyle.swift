import AppKit

struct PointerStyle: Hashable {
    let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init?(rawValue: String) {
        switch rawValue {
        case "paw", "cat01", "cat02", "cat03", "cat04", "cat05", "cat06", "cat07", "cat08", "cat09", "cat10":
            self = .catLaser
            return
        default:
            break
        }
        guard let style = PointerStyle.allCases.first(where: { $0.rawValue == rawValue }) else {
            return nil
        }
        self = style
    }

    static let squeaky = PointerStyle("squeaky")
    static let rocket = PointerStyle("rocket")
    static let catLaser = PointerStyle("catLaser")
    static let catChaser = PointerStyle("catChaser")
    static let catPixel = PointerStyle("catPixel")
    static let catFish = PointerStyle("catFish")
    static let lavender = PointerStyle("lavender")
    static let glove = PointerStyle("glove")
    static let coral = PointerStyle("coral")
    static let plush = PointerStyle("plush")
    static let robot = PointerStyle("robot")
    static let laser = PointerStyle("laser")

    private static let builtIn: [(id: String, title: String, ink: CGColor)] = [
        ("catLaser", "Лапка за лазером", Ink.hex(0xD78461)),
        ("catChaser", "Котик за лазером", Ink.hex(0xD78461)),
        ("catPixel", "Пиксельный кот", Ink.hex(0xD78461)),
        ("catFish", "Котик с рыбкой", Ink.hex(0xD78461)),
        ("funny01", "Весёлая стрелка", Ink.hex(0x7E79E8)),
        ("funny02", "Милая стрелочка", Ink.hex(0x7E79E8)),
        ("funny03", "Алмазный меч", Ink.hex(0x7E79E8)),
        ("funny04", "Карандаш", Ink.hex(0x7E79E8)),
        ("funny05", "Динозаврик", Ink.hex(0x7E79E8)),
        ("funny06", "Инопланетянин", Ink.hex(0x7E79E8)),
        ("funny07", "Пицца", Ink.hex(0x7E79E8)),
        ("funny08", "Морковка", Ink.hex(0x7E79E8)),
        ("funny09", "Мышь-космонавт", Ink.hex(0x7E79E8)),
        ("funny10", "Волшебная палочка", Ink.hex(0x7E79E8)),
        ("funny11", "Nyan Cat", Ink.hex(0x7E79E8)),
        ("funny12", "Космическое зелье", Ink.hex(0x7E79E8)),
        ("funny13", "Северное сияние", Ink.hex(0x7E79E8)),
        ("funny14", "Six Seven", Ink.hex(0x7E79E8)),
        ("funny16", "Это голубь?", Ink.hex(0x7E79E8)),
        ("funny17", "Забери мои деньги", Ink.hex(0x7E79E8)),
        ("funny18", "Бирюзовый пиксель", Ink.hex(0x31B6D2)),
        ("funny19", "Розовый пиксель", Ink.hex(0xDF53B6)),
        ("funny20", "Помни", Ink.hex(0xE74A5A)),
        ("squeaky", "Резиновая игрушка", Ink.hex(0xE67F98)),
        ("rocket", "Карманная ракета", Ink.hex(0x3284B4)),
        ("lavender", "Лавандовая рука", Ink.purple),
        ("glove", "Перчатка", Ink.purple),
        ("coral", "Коралловая рука", Ink.red),
        ("plush", "Плюшевая рука", Ink.hex(0x2F86F0)),
        ("robot", "Робот", Ink.hex(0x16A87A)),
        ("pink", "Жвачка", Ink.hex(0xEE4F98)),
        ("blue", "Небо", Ink.hex(0x2F86F0)),
        ("mint", "Мята", Ink.hex(0x16A87A)),
        ("lemon", "Лимон", Ink.hex(0xF2B705)),
        ("black", "Полночь", Ink.hex(0x1D1D21)),
        ("chrome", "Хром", Ink.hex(0x6B7380)),
        ("holo", "Голограмма", Ink.purple),
        ("fuzzy", "Пушистая", Ink.purple),
        ("wood", "Дерево", Ink.hex(0x9A5E2C)),
        ("marble", "Мрамор", Ink.hex(0x6B7380)),
        ("terrazzo", "Терраццо", Ink.hex(0xF0561D)),
        ("glass", "Стекло", Ink.hex(0x1597E5)),
        ("jelly", "Желе", Ink.hex(0xA33FE6)),
        ("pastel", "Пастель", Ink.hex(0xEE4F98)),
        ("pixel", "Пиксель", Ink.hex(0x1D1D21)),
        ("lowpoly", "Полигональная", Ink.purple),
        ("knit", "Вязаная", Ink.purple),
        ("skeleton", "Скелет", Ink.hex(0x9A5E2C)),
        ("astro", "Космонавт", Ink.hex(0x2F86F0)),
        ("space", "Космос", Ink.red),
        ("monster", "Монстр", Ink.hex(0x3E9E2E)),
        ("water", "Вода", Ink.hex(0x1597E5)),
        ("lava", "Лава", Ink.hex(0xF0561D)),
        ("grass", "Трава", Ink.hex(0x3E9E2E)),
        ("cactus", "Кактус", Ink.hex(0x3E9E2E)),
        ("choco", "Шоколад", Ink.hex(0x9A5E2C)),
        ("cloud", "Облако", Ink.hex(0x2F86F0)),
        ("mech", "Механизм", Ink.hex(0xF0561D)),
        ("neon", "Неон", Ink.hex(0xE0309A)),
        ("leaf", "Лист", Ink.hex(0x3E9E2E)),
        ("cookie", "Пряник", Ink.hex(0x9A5E2C)),
    ]

    static var builtInHands: [PointerStyle] {
        builtIn.map { PointerStyle($0.id) }
    }

    static var catStyles: [PointerStyle] { builtInHands.filter { $0.rawValue.hasPrefix("cat") } }
    static var funStyles: [PointerStyle] { builtInHands.filter { $0.rawValue.hasPrefix("funny") } }
    static var originalStyles: [PointerStyle] { builtInHands.filter { !$0.rawValue.hasPrefix("cat") && !$0.rawValue.hasPrefix("funny") } }

    static var customHands: [PointerStyle] {
        CustomHands.all.map { PointerStyle($0.id) }
    }

    static var allCases: [PointerStyle] {
        builtInHands + customHands + [.laser]
    }

    static let defaultPinned: [PointerStyle] = [.squeaky, .rocket, .catLaser, .lavender, .glove, .laser]

    var isStandaloneCursor: Bool { rawValue == "funny18" || rawValue == "funny19" }

    var isCatFollower: Bool { self == .catLaser || self == .catChaser || self == .catPixel || self == .catFish }

    var isCustom: Bool {
        CustomHands.hand(rawValue) != nil
    }

    var title: String {
        if self == .laser {
            return "Лазерная точка"
        }
        if let custom = CustomHands.hand(rawValue) {
            return custom.name
        }
        return PointerStyle.builtIn.first { $0.id == rawValue }?.title ?? rawValue
    }

    var assetName: String? {
        if self == .laser {
            return nil
        }
        if isCustom {
            return rawValue
        }
        if rawValue == "funny16" { return "hand_funny16_v2" }
        if rawValue == "rocket" { return "hand_rocket_3d" }
        if self == .catLaser { return "hand_cat_laser" }
        if self == .catChaser { return "hand_cat_chaser" }
        if self == .catPixel { return "hand_cat_pixel" }
        if self == .catFish { return "hand_cat_fish" }
        return "hand_\(rawValue)"
    }

    var pressedAssetName: String? {
        switch rawValue {
        case "funny02", "funny17", "catChaser", "catPixel", "catFish":
            return assetName.map { "\($0)_pressed" }
        default:
            return nil
        }
    }

    var inkColor: CGColor {
        if self == .laser {
            return Ink.red
        }
        if let custom = CustomHands.hand(rawValue) {
            return Ink.hex(custom.ink)
        }
        return PointerStyle.builtIn.first { $0.id == rawValue }?.ink ?? Ink.purple
    }

    private static let defaultsKey = "pointerStyle"

    static var saved: PointerStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            if raw == "dot" {
                return .laser
            }
            if raw == "sunny" {
                return .coral
            }
            return raw.flatMap(PointerStyle.init(rawValue:)) ?? .lavender
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

struct HandAsset {
    let image: CGImage
    let aspect: CGFloat
    let handTop: CGFloat
    let tip: CGFloat
    let wrist: CGFloat
    let rodEnd: CGFloat
    let tipX: CGFloat
    let rodX: CGFloat
    let handMinX: CGFloat
    let handMaxX: CGFloat

    private static var cache: [String: HandAsset] = [:]
    private static var recent: [String] = []
    private static let cacheLimit = 2

    static func load(_ name: String) -> HandAsset? {
        if let hit = cache[name] {
            touch(name)
            return hit
        }
        guard let image = loadImage(name), let asset = measure(image, named: name) else {
            return nil
        }
        cache[name] = asset
        touch(name)
        return asset
    }

    private static func touch(_ name: String) {
        recent.removeAll { $0 == name }
        recent.append(name)
        while recent.count > cacheLimit {
            cache[recent.removeFirst()] = nil
        }
    }

    private static var thumbnails: [String: NSImage] = [:]

    static func forget(_ name: String) {
        cache[name] = nil
        recent.removeAll { $0 == name }
        thumbnails[name] = nil
    }

    static func cachedThumbnail(_ name: String) -> NSImage? {
        thumbnails[name]
    }

    static func preloadThumbnails(_ names: [String], done: (() -> Void)? = nil) {
        let missing = names.filter { thumbnails[$0] == nil }
        guard !missing.isEmpty else {
            done?()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var built: [(String, NSImage)] = []
            for name in missing {
                autoreleasepool {
                    if let image = loadImage(name), let thumb = measure(image, named: name)?.thumbnail {
                        built.append((name, thumb))
                    }
                }
            }
            DispatchQueue.main.async {
                for (name, thumb) in built where thumbnails[name] == nil {
                    thumbnails[name] = thumb
                }
                done?()
            }
        }
    }

    static func thumbnail(_ name: String) -> NSImage? {
        if let hit = thumbnails[name] {
            return hit
        }
        let asset = cache[name] ?? loadImage(name).flatMap { measure($0, named: name) }
        guard let thumb = asset?.thumbnail else {
            return nil
        }
        thumbnails[name] = thumb
        return thumb
    }

    var thumbnail: NSImage {
        let h = CGFloat(image.height)
        let w = CGFloat(image.width)
        let handW = (handMaxX - handMinX) * w
        let handH = (wrist - handTop) * h
        let side = max(handW, handH) * 1.06
        let cx = (handMinX + handMaxX) / 2 * w
        let cy = (handTop + wrist) / 2 * h
        let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        let cropped = image.cropping(to: rect) ?? image
        let px = 128
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(cgImage: cropped, size: NSSize(width: 64, height: 64))
        }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: px, height: px))
        guard let small = ctx.makeImage() else {
            return NSImage(cgImage: cropped, size: NSSize(width: 64, height: 64))
        }
        return NSImage(cgImage: small, size: NSSize(width: 64, height: 64))
    }

    static func resized(_ image: CGImage, height: Int) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * CGFloat(height) / CGFloat(image.height)).rounded()))
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func measure(_ image: CGImage, named name: String) -> HandAsset? {
        switch name {
        case "hand_cat_laser", "hand_cat_chaser", "hand_cat_chaser_pressed",
             "hand_cat_pixel", "hand_cat_pixel_pressed", "hand_cat_fish", "hand_cat_fish_pressed",
             "hand_funny18", "hand_funny19":
            return measureStandalone(image)
        default:
            return measure(image)
        }
    }

    // Standalone cursors have no rod; their uppermost opaque pixel is the hotspot.
    private static func measureStandalone(_ image: CGImage) -> HandAsset? {
        let w = image.width, h = image.height
        var alpha = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1, top = h, bottom = -1
        for y in 0..<h {
            for x in 0..<w where alpha[y * w + x] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard bottom > top, maxX >= minX else { return nil }
        var tipMin = w, tipMax = -1
        for x in 0..<w where alpha[top * w + x] > 128 { tipMin = min(tipMin, x); tipMax = max(tipMax, x) }
        guard tipMax >= tipMin else { return nil }
        let wf = CGFloat(w), hf = CGFloat(h)
        let tipX = (CGFloat(tipMin + tipMax) / 2 + 0.5) / wf
        let tipY = (CGFloat(top) + 0.5) / hf
        return HandAsset(image: image, aspect: wf / hf, handTop: CGFloat(top) / hf,
                         tip: tipY, wrist: CGFloat(bottom + 1) / hf,
                         rodEnd: CGFloat(bottom + 1) / hf, tipX: tipX, rodX: tipX,
                         handMinX: CGFloat(minX) / wf, handMaxX: CGFloat(maxX + 1) / wf)
    }

    private static func measure(_ image: CGImage) -> HandAsset? {
        let w = image.width
        let h = image.height
        var alpha = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func count(_ y: Int) -> Int {
            var n = 0
            let row = y * w
            for x in 0..<w where alpha[row + x] > 128 {
                n += 1
            }
            return n
        }
        func center(_ y: Int) -> CGFloat {
            let row = y * w
            var lo = -1
            var hi = -1
            for x in 0..<w where alpha[row + x] > 128 {
                if lo < 0 {
                    lo = x
                }
                hi = x
            }
            return lo < 0 ? 0.5 : CGFloat(lo + hi) / 2 / CGFloat(w)
        }

        let counts = (0..<h).map(count)
        guard let top = counts.firstIndex(where: { $0 > 0 }) else {
            return nil
        }
        let searchEnd = min(h, top + Int(0.45 * Double(h)))
        let maxW = counts[top..<searchEnd].max() ?? 0
        guard maxW > 0,
              let fist = (top..<h).first(where: { Double(counts[$0]) > 0.6 * Double(maxW) }),
              let wrist = (fist..<h).first(where: { Double(counts[$0]) < 0.35 * Double(maxW) }) else {
            return nil
        }
        let rodW = counts[min(h - 1, wrist + h / 50)]
        let lastRow = counts.lastIndex(where: { $0 > 0 }) ?? (h - 1)
        let from = min(h - 1, wrist + h / 33)
        let handle = (from..<h).first(where: { Double(counts[$0]) > 1.8 * Double(rodW) })
        let rodEnd = handle ?? lastRow

        var minX = w
        var maxX = 0
        for y in top..<wrist {
            let row = y * w
            for x in 0..<w where alpha[row + x] > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }

        let fh = CGFloat(h)
        return HandAsset(
            image: image,
            aspect: CGFloat(w) / fh,
            handTop: max(0, CGFloat(top) - 0.004 * fh) / fh,
            tip: CGFloat(top) / fh,
            wrist: CGFloat(wrist) / fh,
            rodEnd: CGFloat(rodEnd) / fh,
            tipX: center(min(h - 1, top + h / 200)),
            rodX: center((wrist + rodEnd) / 2),
            handMinX: CGFloat(minX) / CGFloat(w),
            handMaxX: CGFloat(maxX) / CGFloat(w)
        )
    }

    private static func loadImage(_ name: String) -> CGImage? {
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var urls: [URL] = []
        urls.append(CustomHands.directory.appendingPathComponent("\(name).png"))
        if let u = Bundle.main.url(forResource: name, withExtension: "png") {
            urls.append(u)
        }
        urls.append(exeDir.appendingPathComponent("\(name).png"))
        urls.append(exeDir.appendingPathComponent("assets/\(name).png"))
        urls.append(URL(fileURLWithPath: "assets/\(name).png"))
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
        }
        return nil
    }
}
