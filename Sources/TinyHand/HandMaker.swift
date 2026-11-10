import AppKit

enum HandMaker {
    private static let canvasW = 1024
    private static let canvasH = 1536
    private static let headBottom: CGFloat = 710
    static var wristFraction: CGFloat { headBottom / CGFloat(canvasH) }

    static func prompt(for idea: String) -> String {
        let trimmed = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = trimmed.isEmpty ? "яркая игрушечная рука-указатель" : trimmed
        return """
        Создай один наконечник указателя для приложения PlayPointer: \(subject).
        Один цельный объект расположен вертикально, целиком в кадре, с небольшим свободным полем со всех сторон. Выразительный кончик указателя находится в самой верхней точке объекта. Силуэт должен хорошо читаться в маленьком размере.
        Прозрачный фон с настоящим альфа-каналом, PNG. Без фоновой шахматки, текста, пола, тени и свечения. Без палочки или стержня: приложение добавит их самостоятельно. Не обрезай объект.
        """
    }

    struct Problem: Error {
        let message: String
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            rgba[(y * width + x) * 4 + 3]
        }
    }

    static func make(from url: URL) throws -> (image: CGImage, ink: UInt32) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Problem(message: "PlayPointer не может прочитать это изображение.")
        }
        let pixels = try read(image)
        try check(pixels)
        guard let composed = compose(image, pixels) else {
            throw Problem(message: "Не удалось добавить стержень к объекту. Попробуйте другое изображение.")
        }
        return (composed, ink(pixels))
    }

    private static func read(_ image: CGImage) throws -> Pixels {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            throw Problem(message: "Сохраните изображение в PNG с прозрачным фоном.")
        default:
            break
        }
        let w = image.width
        let h = image.height
        guard w >= 64, h >= 64 else {
            throw Problem(message: "Высота изображения должна быть не меньше 512 пикселей.")
        }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Problem(message: "PlayPointer не может прочитать это изображение.")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(width: w, height: h, rgba: rgba)
    }

    private static func check(_ p: Pixels) throws {
        let w = p.width
        let h = p.height
        var edge = 0
        var edgeSolid = 0
        for x in 0..<w {
            edge += 2
            edgeSolid += (p.alpha(x, 0) > 32 ? 1 : 0) + (p.alpha(x, h - 1) > 32 ? 1 : 0)
        }
        for y in 0..<h {
            edge += 2
            edgeSolid += (p.alpha(0, y) > 32 ? 1 : 0) + (p.alpha(w - 1, y) > 32 ? 1 : 0)
        }
        if Double(edgeSolid) / Double(edge) > 0.02 {
            throw Problem(message: "Проверьте фон и края. Фон должен быть прозрачным, а вокруг объекта нужно оставить место.")
        }

        guard let box = bounds(p) else {
            throw Problem(message: "В файле нет видимого изображения.")
        }
        let bh = box.maxY - box.minY + 1
        if Double(bh) / Double(h) < 0.3 {
            throw Problem(message: "Объект слишком маленький. Обрежьте лишнее пространство вокруг него.")
        }


    }

    private static func bounds(_ p: Pixels) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = p.width
        var minY = p.height
        var maxX = -1
        var maxY = -1
        for y in 0..<p.height {
            for x in 0..<p.width where p.alpha(x, y) > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, minY, maxX, maxY)
    }

    private static func bottomCenter(_ p: Pixels, _ box: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> Double {
        let bh = box.maxY - box.minY + 1
        var lo = p.width
        var hi = -1
        for y in max(box.minY, box.maxY - max(2, bh * 4 / 100))...box.maxY {
            for x in box.minX...box.maxX where p.alpha(x, y) > 128 {
                lo = min(lo, x)
                hi = max(hi, x)
            }
        }
        return hi < 0 ? Double(box.minX + box.maxX) / 2 : Double(lo + hi) / 2
    }

    private static func compose(_ image: CGImage, _ p: Pixels) -> CGImage? {
        guard let box = bounds(p) else {
            return nil
        }
        let handHeight: CGFloat = 560
        let bw = CGFloat(box.maxX - box.minX + 1)
        let bh = CGFloat(box.maxY - box.minY + 1)
        let center = Int(bottomCenter(p, box).rounded())
        let centerBottom = stride(from: box.maxY, through: box.minY, by: -1)
            .first { p.alpha(center, $0) > 128 }
        let attachmentX = centerBottom == nil
            ? (box.minX...box.maxX).filter { p.alpha($0, box.maxY) > 128 }
                .min { abs($0 - center) < abs($1 - center) } ?? center
            : center
        let wristX = CGFloat(attachmentX) + 0.5
        let halfWidth = CGFloat(canvasW) / 2
        let reach = max(wristX - CGFloat(box.minX), CGFloat(box.maxX + 1) - wristX)
        let scale = min(handHeight / bh, 700 / bw, (halfWidth - 32) / reach)
        let drawW = CGFloat(p.width) * scale
        let drawH = CGFloat(p.height) * scale
        let originX = halfWidth - wristX * scale
        let originTop = headBottom - CGFloat(box.maxY + 1) * scale

        guard let ctx = CGContext(data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high

        let rodW = min(76, max(54, bw * scale * 0.18))
        let attachmentY = originTop + CGFloat((centerBottom ?? box.maxY) + 1) * scale
        let rodTop = min(headBottom - 30, attachmentY - rodW / 2 - 4)
        let rodBottom: CGFloat = 1462
        let rod = CGRect(x: CGFloat(canvasW) / 2 - rodW / 2, y: CGFloat(canvasH) - rodBottom,
                         width: rodW, height: rodBottom - rodTop)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rod, cornerWidth: rodW / 2, cornerHeight: rodW / 2, transform: nil))
        ctx.clip()
        let colors = [Ink.hex(0x000000), Ink.hex(0x121214), Ink.hex(0x3A3A3E), Ink.hex(0x121214), Ink.hex(0x000000)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                     locations: [0, 0.22, 0.45, 0.75, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: rod.minX, y: 0), end: CGPoint(x: rod.maxX, y: 0), options: [])
        }
        ctx.restoreGState()

        ctx.draw(image, in: CGRect(x: originX, y: CGFloat(canvasH) - originTop - drawH, width: drawW, height: drawH))
        return ctx.makeImage()
    }

    private static func ink(_ p: Pixels) -> UInt32 {
        var best: (score: Double, r: Double, g: Double, b: Double) = (-1, 0.53, 0.33, 0.95)
        var buckets: [Int: (n: Int, r: Double, g: Double, b: Double)] = [:]
        for y in stride(from: 0, to: p.height, by: 3) {
            for x in stride(from: 0, to: p.width, by: 3) {
                let i = (y * p.width + x) * 4
                let a = Double(p.rgba[i + 3])
                guard a > 200 else {
                    continue
                }
                let r = Double(p.rgba[i]) / a
                let g = Double(p.rgba[i + 1]) / a
                let b = Double(p.rgba[i + 2]) / a
                let key = Int(r * 5) * 36 + Int(g * 5) * 6 + Int(b * 5)
                var e = buckets[key] ?? (0, 0, 0, 0)
                e.n += 1
                e.r += r
                e.g += g
                e.b += b
                buckets[key] = e
            }
        }
        for e in buckets.values {
            let r = e.r / Double(e.n)
            let g = e.g / Double(e.n)
            let b = e.b / Double(e.n)
            let hi = max(r, g, b)
            let lo = min(r, g, b)
            let sat = hi == 0 ? 0 : (hi - lo) / hi
            let lum = 0.3 * r + 0.59 * g + 0.11 * b
            let score = Double(e.n) * (0.25 + sat) * (lum > 0.12 && lum < 0.85 ? 1 : 0.15)
            if score > best.score {
                best = (score, r, g, b)
            }
        }
        let hi = max(best.r, best.g, best.b)
        let lo = min(best.r, best.g, best.b)
        var r = best.r
        var g = best.g
        var b = best.b
        if hi - lo < 0.08 {
            r = 0.42
            g = 0.45
            b = 0.5
        } else if hi > 0.82 {
            r *= 0.82 / hi
            g *= 0.82 / hi
            b *= 0.82 / hi
        }
        return UInt32(min(255, r * 255)) << 16 | UInt32(min(255, g * 255)) << 8 | UInt32(min(255, b * 255))
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Problem(message: "Не удалось сохранить изображение руки.")
        }
        try data.write(to: url, options: .atomic)
    }
}

struct CustomHand: Codable {
    let id: String
    var name: String
    let ink: UInt32
}

enum CustomHands {
    static let changed = Notification.Name("PlayPointerCustomHandsChanged")

    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["TH_HANDS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PlayPointer/Hands", isDirectory: true)
    }

    private static var listURL: URL {
        directory.appendingPathComponent("hands.json")
    }

    private static var loaded: [CustomHand]?

    static var all: [CustomHand] {
        if let loaded = loaded {
            return loaded
        }
        let list = (try? Data(contentsOf: listURL)).flatMap { try? JSONDecoder().decode([CustomHand].self, from: $0) } ?? []
        loaded = list
        return list
    }

    static func hand(_ id: String) -> CustomHand? {
        guard id.hasPrefix("custom-") else {
            return nil
        }
        return all.first { $0.id == id }
    }

    @discardableResult
    static func add(_ image: CGImage, ink: UInt32, name: String) throws -> PointerStyle {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = "custom-" + UUID().uuidString.prefix(8).lowercased()
        try HandMaker.write(image, to: directory.appendingPathComponent("\(id).png"))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = all
        list.append(CustomHand(id: id, name: trimmed.isEmpty ? "Мой указатель \(list.count + 1)" : String(trimmed.prefix(16)), ink: ink))
        try save(list)
        guard let style = PointerStyle(rawValue: id) else {
            throw HandMaker.Problem(message: "Не удалось добавить указатель в список.")
        }
        return style
    }

    static func remove(_ style: PointerStyle) {
        guard let assetName = style.assetName, style.isCustom else {
            return
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(assetName).png"))
        HandAsset.forget(assetName)
        try? save(all.filter { $0.id != style.rawValue })
    }

    private static func save(_ list: [CustomHand]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: listURL, options: .atomic)
        loaded = list
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func suggestedName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let words = base.split(separator: " ").prefix(2).joined(separator: " ")
        guard !words.isEmpty, words.count <= 16, !words.lowercased().hasPrefix("chatgpt image") else {
            return "Мой указатель \(all.count + 1)"
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
