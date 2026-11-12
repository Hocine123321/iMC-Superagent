import SwiftUI
import UIKit

/// Which orientations the launcher window allows. Portrait, except while the touch editor is open.
@objc(HZLauncherOrientation)
public final class LauncherOrientation: NSObject {
    @objc public static var mask: UIInterfaceOrientationMask = .portrait

    static func request(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            NSLog("iMC orientation request failed: %@", error.localizedDescription)
        }
    }
}

/// The layout being edited: ten buttons, each a nudge from where the game puts it. Saved at once, in the file the game reads.
@MainActor
final class TouchEditorModel: ObservableObject {
    @Published var slots: [TouchSlot]
    @Published var selected: Int? = nil
    @Published var marginIndex: Int

    private var existing: String
    private var dragStart: (rect: CGRect, base: CGRect)? = nil

    static let margins: [CGFloat] = [0, 0.5, 1, 1.5]

    init() {
        let text = DiagFiles.text(TouchLayoutFile.path) ?? ""
        existing = text
        slots = TouchLayoutFile.parse(text)
        let store = ImcStore()
        marginIndex = store.int("safeMargin")
    }

    var margin: CGFloat { Self.margins[min(max(marginIndex, 0), Self.margins.count - 1)] }
    var customised: Int { slots.prefix(10).filter { !$0.isDefault }.count }

    func base(_ pad: TouchPad, in size: CGSize) -> CGRect { pad.base(in: size, margin: margin) }
    func rect(_ pad: TouchPad, in size: CGSize) -> CGRect { slots[pad.id].place(base(pad, in: size), in: size) }

    func drag(_ pad: TouchPad, translation: CGSize, in size: CGSize) {
        let base = self.base(pad, in: size)
        if dragStart == nil { dragStart = (rect(pad, in: size), base) }
        guard let start = dragStart else { return }
        selected = pad.id
        // The target is where the finger took the button, kept fully on the screen.
        var target = start.rect.offsetBy(dx: translation.width, dy: translation.height)
        target.origin.x = max(0, min(target.origin.x, size.width - target.width))
        target.origin.y = max(0, min(target.origin.y, size.height - target.height))
        var s = slots[pad.id].moved(base: base, to: target, in: size)
        s.shown = slots[pad.id].shown
        slots[pad.id] = s
    }

    func endDrag() {
        dragStart = nil
        save()
    }

    func update(_ id: Int, _ change: (inout TouchSlot) -> Void) {
        var s = slots[id]
        change(&s)
        slots[id] = s.clamped()
    }

    func reset(_ id: Int) { slots[id] = TouchSlot(); save() }
    func resetAll() { slots = Array(repeating: TouchSlot(), count: slots.count); selected = nil; save() }

    func save() {
        let text = TouchLayoutFile.serialize(slots, keeping: existing)
        try? FileManager.default.createDirectory(atPath: DiagFiles.home, withIntermediateDirectories: true)
        if text.isEmpty { try? FileManager.default.removeItem(atPath: TouchLayoutFile.path) }
        else { try? text.write(toFile: TouchLayoutFile.path, atomically: true, encoding: .utf8) }
        existing = text
    }
}

/// A mock of the game screen at the phone's own proportions, with the buttons where the game puts them.
struct TouchCanvas: View {
    @ObservedObject var model: TouchEditorModel
    var interactive = true
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack(alignment: .topLeading) {
                scene(size)
                ForEach(TouchPad.all) { pad in padView(pad, size) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: interactive ? 0 : 18, style: .continuous))
        }
    }

    private func scene(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.32), Color(red: 0.35, green: 0.12, blue: 0.28)], startPoint: .top, endPoint: .bottom)
            // Ground: a row of blocks.
            Canvas { ctx, s in
                let cell = s.height * 0.12
                let top = s.height * 0.72
                for c in 0..<Int(s.width / cell) + 1 {
                    let h = CGFloat(abs((c &* 2654435761) % 3))
                    let y = top + h * cell * 0.5
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: y, width: cell - 1, height: s.height - y)), with: .color((c % 2 == 0 ? brand : brand2).opacity(0.28)))
                }
            }
            // The look area and the steering area, as the game splits the screen.
            Rectangle().fill(brand.opacity(0.07)).frame(width: size.width * 0.4, height: size.height)
            Text("Steer").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                .position(x: size.width * 0.2, y: size.height * 0.5)
            Text("Look").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                .position(x: size.width * 0.62, y: size.height * 0.5)
            // Crosshair and hotbar, where the game draws them (the hotbar sits on the top edge between the slot buttons).
            Image(systemName: "plus").font(.system(size: size.height * 0.07, weight: .light)).foregroundStyle(.white.opacity(0.75))
                .position(x: size.width * 0.5, y: size.height * 0.5)
            HStack(spacing: 2) {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(i == 0 ? 0.35 : 0.14)).aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(width: size.width * 0.38, height: size.height * 0.09)
            .position(x: size.width * 0.5, y: size.height * 0.04 + size.height * 0.065)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder private func padView(_ pad: TouchPad, _ size: CGSize) -> some View {
        let slot = model.slots[pad.id]
        let r = model.rect(pad, in: size)
        let isSelected = model.selected == pad.id
        let content = ZStack {
            RoundedRectangle(cornerRadius: min(r.width, r.height) * 0.22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: min(r.width, r.height) * 0.22, style: .continuous)
                .strokeBorder(isSelected ? brand : Color.white.opacity(0.35), style: StrokeStyle(lineWidth: isSelected ? 3 : 1, dash: slot.shown ? [] : [5, 4]))
            Text(pad.label).font(.system(size: max(9, min(r.width * 0.28, r.height * 0.3)), weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: r.width, height: r.height)
        .opacity(slot.shown ? slot.opacity : 0.35)
        .position(x: r.midX, y: r.midY)
        if interactive {
            content
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in model.drag(pad, translation: v.translation, in: size) }
                        .onEnded { _ in model.endDrag() }
                )
                .accessibilityLabel(pad.title)
        } else {
            content
        }
    }
}

/// The full-screen editor. Landscape, like the game: drag a button to move it, tap it to resize or hide it.
struct TouchEditorScreen: View {
    @StateObject private var model = TouchEditorModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { g in
                let aspect = TouchEditorScreen.deviceAspect
                let fit: CGSize = {
                    let w = min(g.size.width, g.size.height * aspect)
                    return CGSize(width: w, height: w / aspect)
                }()
                TouchCanvas(model: model)
                    .frame(width: fit.width, height: fit.height)
                    .overlay(alignment: .bottom) { inspector.padding(10) }
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
            VStack {
                HStack {
                    Button { model.save(); dismiss() } label: { Label("Done", systemImage: "checkmark").font(.headline).padding(.horizontal, 6) }
                        .primaryAction().tint(brand)
                    Spacer()
                    Text(model.selected == nil ? "Drag a button to move it" : "Drag to move, or use the controls")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12).padding(.vertical, 7).glassCapsule()
                    Spacer()
                    Button(role: .destructive) { confirmReset = true } label: { Label("Reset all", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.semibold)) }
                        .secondaryAction().tint(brand2).disabled(model.customised == 0)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { LauncherOrientation.request(.landscape) }
        .onDisappear { model.save(); LauncherOrientation.request(.portrait) }
        .alert("Reset every button?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All buttons go back to the standard layout.") }
    }

    /// The device's own landscape proportions, so the canvas is the shape of the game screen.
    static var deviceAspect: CGFloat {
        let b = UIScreen.main.nativeBounds
        let long = max(b.width, b.height), short = max(1, min(b.width, b.height))
        return long / short
    }

    @ViewBuilder private var inspector: some View {
        if let id = model.selected, let pad = TouchPad.all.first(where: { $0.id == id }) {
            let slot = model.slots[id]
            HStack(spacing: 18) {
                Text(pad.title).font(.subheadline.weight(.bold)).frame(minWidth: 70, alignment: .leading)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                    Slider(value: Binding(get: { slot.scale }, set: { v in model.update(id) { $0.scale = v } }), in: TouchSlot.minScale...TouchSlot.maxScale, onEditingChanged: { editing in
                        if !editing { model.save() }
                    }).frame(width: 120)
                }
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled").font(.caption)
                    Slider(value: Binding(get: { slot.opacity }, set: { v in model.update(id) { $0.opacity = v } }), in: TouchSlot.minOpacity...1, onEditingChanged: { editing in
                        if !editing { model.save() }
                    }).frame(width: 100)
                }
                Toggle("Show", isOn: Binding(get: { slot.shown }, set: { v in model.update(id) { $0.shown = v }; model.save() })).labelsHidden()
                Button { model.reset(id) } label: { Image(systemName: "arrow.counterclockwise") }.secondaryAction().disabled(slot.isDefault)
                Button { model.selected = nil } label: { Image(systemName: "xmark") }.secondaryAction()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCard(cornerRadius: 22)
        }
    }
}
