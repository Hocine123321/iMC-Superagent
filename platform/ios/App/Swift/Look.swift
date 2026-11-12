import SwiftUI
import Combine
import UIKit

// iMC's look. The glass is ONLY the system's: `glassEffect`, `GlassEffectContainer`, `.glass` and `.glassProminent`
// on iOS 26 and later, the system's own materials before that. Nothing here draws a glass imitation.

// MARK: - The ground behind every screen

/// The whole ground behind a screen, drawn ONCE into a single bitmap: navy at the top, wine at the bottom, a blue glow
/// and a red glow in the corners, and a faint grid of squares like a block world seen from above, fading out downwards.
/// "Colour balance" in Settings moves the mix; "Backdrop colour" sets how strong it is.
///
/// The first version was a ZStack of a linear gradient, two radial gradients and a masked Canvas, rebuilt for every tab
/// and pushed page. Liquid Glass samples whatever is behind it on every frame it moves, so each card over that stack
/// made the system composite four layers again while scrolling. One flat image behind the glass costs a texture read.
/// The bitmap is kept for the last size, colours and mix, so a new screen reuses it and only a change in Settings
/// draws it again.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @ObservedObject private var look = BackdropLook.shared

    var body: some View {
        GeometryReader { geo in
            if let image = BackdropCache.image(size: geo.size, scheme: scheme, brand: brand, brand2: brand2,
                                               strength: look.strength, balance: look.balance) {
                Image(uiImage: image).resizable().frame(width: geo.size.width, height: geo.size.height)
            } else {
                Palette.ink
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Only what the backdrop depends on, so a change to any other setting does not redraw it (and a screen that shows the
/// backdrop does not observe every preference in the app).
final class BackdropLook: ObservableObject {
    static let shared = BackdropLook()
    @Published private(set) var strength: Double
    @Published private(set) var balance: Double
    private var watch: AnyCancellable?
    private init() {
        strength = Prefs.shared.intensity
        balance = Prefs.shared.balance
        watch = Prefs.shared.objectWillChange
            .receive(on: DispatchQueue.main)          // after the change has landed
            // A slider drag changes these sixty times a second; the picture is drawn at most about ten times a second
            // while it moves, and once more when it stops.
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                let s = Prefs.shared.intensity, b = Prefs.shared.balance
                if s != self.strength { self.strength = s }
                if b != self.balance { self.balance = b }
            }
    }
}

enum BackdropCache {
    private static var key = ""
    private static var cached: UIImage?

    static func image(size: CGSize, scheme: ColorScheme, brand: Color, brand2: Color, strength: Double, balance: Double) -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        // The palette is dynamic (one colour for dark, one for light): resolve it for the scheme being drawn.
        let ink = UIColor(Palette.ink).resolvedColor(with: traits)
        let wine = UIColor(Palette.wine).resolvedColor(with: traits)
        let c1 = UIColor(brand).resolvedColor(with: traits)
        let c2 = UIColor(brand2).resolvedColor(with: traits)
        func rgb(_ c: UIColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "%.3f,%.3f,%.3f", r, g, b)
        }
        let k = "\(Int(size.width))x\(Int(size.height))/\(scheme == .dark)/\(rgb(c1))/\(rgb(c2))/\(String(format: "%.2f", strength))/\(String(format: "%.2f", balance))"
        if k == key, let cached { return cached }

        let s = strength * 2                                          // 1 at the default
        let base = scheme == .dark ? 0.50 : 0.30
        // Balance 0 is all brand, 1 is all the other one; the middle is an even mix.
        let a1 = min(0.95, base * s * min(1.4, 2 * (1 - balance)))
        let a2 = min(0.95, base * s * min(1.4, 2 * balance))

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = min(format.scale, 2)                           // smooth gradients need no more
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            func gradient(_ colours: [UIColor], _ locations: [CGFloat]) -> CGGradient {
                CGGradient(colorsSpace: space, colors: colours.map { $0.cgColor } as CFArray, locations: locations)!
            }
            // Navy to wine, top to bottom.
            ctx.drawLinearGradient(gradient([ink, wine], [0, 1]), start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // The two glows, clear at their edge.
            func glow(_ colour: UIColor, alpha: Double, at centre: CGPoint, radius: CGFloat) {
                ctx.drawRadialGradient(gradient([colour.withAlphaComponent(alpha), colour.withAlphaComponent(0)], [0, 1]),
                                       startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
            }
            glow(c1, alpha: a1, at: .zero, radius: 560)
            glow(c2, alpha: a2, at: CGPoint(x: size.width, y: size.height), radius: 620)
            // The grid, fading out downwards (the mask the old version used, applied while drawing).
            let cell: CGFloat = 36
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
            for r in 0..<rows {
                for col in 0..<cols {
                    // A fixed pseudo-random pattern (no animation, no state): the same picture every time.
                    let h = (r &* 73856093) ^ (col &* 19349663)
                    let v = Double(abs(h % 1000)) / 1000
                    guard v > 0.58 else { continue }
                    let rect = CGRect(x: CGFloat(col) * cell + 2, y: CGFloat(r) * cell + 2, width: cell - 4, height: cell - 4)
                    let fade = max(0, 1 - Double(rect.midY / size.height))
                    ctx.setFillColor(((h & 4) == 0 ? c1 : c2).withAlphaComponent((0.05 + (v - 0.58) * 0.30) * fade).cgColor)
                    ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 6).cgPath)
                    ctx.fillPath()
                }
            }
        }
        key = k
        cached = image
        return image
    }
}

// MARK: - System glass

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// A card of system Liquid Glass on iOS 26 and later; the system's material before that.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
        }
    }

    /// The same in a capsule: chips, small status pills.
    @ViewBuilder func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        }
    }

    @ViewBuilder func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: Circle())
        } else {
            self.background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
        }
    }

    @ViewBuilder func primaryAction() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder func secondaryAction() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }

    /// A round button. `buttonBorderShape(.circle)` needs iOS 17; the deployment target is 16.
    @ViewBuilder func circleShape() -> some View {
        if #available(iOS 17.0, *) { self.buttonBorderShape(.circle) } else { self }
    }

    /// The scroll content of a screen: the backdrop behind it, side margins and room under the tab bar.
    func screenBackground() -> some View {
        self.background(Backdrop())
    }
}

/// Groups nearby glass so the system can blend and morph it as one piece (iOS 26); a plain container before that.
struct GlassStack<Content: View>: View {
    var spacing: CGFloat
    let content: Content
    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    // Deliberately NOT a GlassEffectContainer. A container merges glass shapes that sit within `spacing` of each
    // other into one blob, which pinched the Share / Copy / trash buttons and the Marketplace tabs into waisted
    // shapes (owner's screenshots, 2026-11-12), and it makes the system re-evaluate every shape as the list
    // scrolls. Each card and chip here is meant to stay its own shape, so they stand alone. The parameters stay
    // so the call sites do not change.
    var body: some View { content }
}

// MARK: - Building blocks

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold)).tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One glass card holding rows. Put `Sep()` between rows.
struct GlassGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 24)
    }
}

/// The thin line between two rows, starting under the text (after the icon tile).
struct Sep: View {
    var inset: CGFloat = 62
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5).padding(.leading, inset)
    }
}

/// A rounded square with a symbol on a blue or red gradient: the icon of a row.
struct IconTile: View {
    enum Tone { case brand, brand2, neutral, ok, warn }
    let symbol: String
    var tone: Tone = .brand
    var size: CGFloat = 34
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    private var colours: [Color] {
        switch tone {
        case .brand: return [brand, Palette.blueDeep.opacity(0.9)]
        case .brand2: return [brand2, Palette.redDeep.opacity(0.9)]
        case .neutral: return [Color.gray, Color.gray.opacity(0.7)]
        case .ok: return [Palette.ok, Palette.ok.opacity(0.7)]
        case .warn: return [Palette.warn, Palette.warn.opacity(0.7)]
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colours, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The label of a row that opens something: icon tile, title, a grey line, a chevron.
struct RowLabel: View {
    let symbol: String
    var tone: IconTile.Tone = .brand
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var chevron = true

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A switch row.
struct ToggleRow: View {
    let symbol: String
    var tone: IconTile.Tone = .brand
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A small coloured dot with a word: the state of something.
struct StatusPill: View {
    enum Kind { case ok, warn, bad, info }
    let kind: Kind
    let text: String
    private var colour: Color {
        switch kind {
        case .ok: return Palette.ok
        case .warn: return Palette.warn
        case .bad: return Palette.red
        case .info: return Palette.blue
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassCapsule()
    }
}

/// A bar that fills from blue to red.
struct MixBar: View {
    let fraction: Double
    var height: CGFloat = 10
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [brand, brand2], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// Long text (logs, licences) in pieces, so only what is on screen is laid out.
struct LongText: View {
    let text: String
    var font: Font = .system(size: 11, design: .monospaced)
    var linesPerChunk = 40

    /// Split once per text. The first version split and joined every line of a log (up to 256 KB) each time the body was
    /// evaluated, which is every time anything in the page changed, a keystroke in the search box included.
    @State private var chunks: [String] = []
    @State private var splitFrom: Int = -1

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk).font(font).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { split() }
        .onChange(of: text) { _ in split() }
    }

    private func split() {
        let key = text.hashValue
        guard key != splitFrom else { return }
        splitFrom = key
        let lines = text.components(separatedBy: "\n")
        chunks = stride(from: 0, to: lines.count, by: linesPerChunk).map {
            lines[$0..<min($0 + linesPerChunk, lines.count)].joined(separator: "\n")
        }
    }
}

// MARK: - The mark

/// The app's mark: an isometric block, blue on one side and red on the other, with a bright top. Drawn in code so it
/// is the same picture as the app icon (tools/make_app_icon.py) at any size.
struct BrandMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let r = s * 0.5, h = r * 0.8660254
            let cx = g.size.width / 2, cy = g.size.height / 2
            let t = CGPoint(x: cx, y: cy - r), tr = CGPoint(x: cx + h, y: cy - r / 2), br = CGPoint(x: cx + h, y: cy + r / 2)
            let b = CGPoint(x: cx, y: cy + r), bl = CGPoint(x: cx - h, y: cy + r / 2), tl = CGPoint(x: cx - h, y: cy - r / 2)
            let c = CGPoint(x: cx, y: cy)
            ZStack {
                Path { p in p.move(to: tl); p.addLine(to: c); p.addLine(to: b); p.addLine(to: bl); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.47, blue: 1.0), Color(red: 0.10, green: 0.22, blue: 0.70)],
                                         startPoint: .top, endPoint: .bottom))
                Path { p in p.move(to: c); p.addLine(to: tr); p.addLine(to: br); p.addLine(to: b); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.32, blue: 0.38), Color(red: 0.66, green: 0.08, blue: 0.20)],
                                         startPoint: .top, endPoint: .bottom))
                Path { p in p.move(to: t); p.addLine(to: tr); p.addLine(to: c); p.addLine(to: tl); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color.white, Color(red: 0.78, green: 0.86, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: tl); p.addLine(to: c); p.addLine(to: tr)
                    p.move(to: c); p.addLine(to: b)
                }
                .stroke(Color.white.opacity(0.55), lineWidth: max(1, s * 0.012))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
