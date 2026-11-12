import SwiftUI

/// A stepped setting: a title, one line of help and a menu of the choices.
struct ChoiceRow: View {
    let symbol: String
    var tone: IconTile.Tone = .brand
    let title: String
    var detail: String? = nil
    let names: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
            }
            .pickerStyle(.menu).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// The game's touch controls and performance, edited from the launcher: the same settings as the game's iMC Settings
/// page, written to the same file. Plus the button layout editor.
struct ControlsTab: View {
    @StateObject private var store = ImcStore()
    @StateObject private var preview = TouchEditorModel()
    @State private var editing = false
    @State private var confirmReset = false
    @State private var confirmLayoutReset = false
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    private let look = ["Slowest", "Slow", "Normal", "Fast", "Fastest"]
    private let size = ["Small", "Normal", "Large", "Largest"]
    private let zone = ["Narrow", "Normal", "Wide", "Widest"]
    private let hold = ["Very short", "Short", "Normal", "Long"]
    private let margin = ["None", "Small", "Normal", "Large"]
    private let menu = ["Precise", "Normal", "Careful", "Very careful", "Firm"]
    private let shift = ["-16", "-8", "0", "+8", "+16"]
    private let reacts = ["Relaxed", "Balanced", "Early"]
    private let distances = ["2 chunks", "4 chunks", "6 chunks", "8 chunks", "10 chunks", "12 chunks"]

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassStack(spacing: 18) {
                    VStack(spacing: 16) {
                        layoutCard
                        SectionLabel("Buttons")
                        GlassGroup {
                            ToggleRow(symbol: "hand.tap.fill", title: "On-screen buttons", detail: "Show the buttons on the screen while you play.", isOn: store.binding("touchControls"))
                            Sep()
                            ChoiceRow(symbol: "rectangle.dashed", tone: .brand2, title: "Screen margin", detail: "Keeps the buttons away from the notch, the corners and the home bar.",
                                      names: margin, selection: store.stepBinding("safeMargin"))
                        }
                        SectionLabel("Looking and moving")
                        GlassGroup {
                            ChoiceRow(symbol: "eye.fill", title: "Look speed", detail: "How far the view turns when you drag across the world.", names: look, selection: store.stepBinding("lookSpeed"))
                            Sep()
                            ChoiceRow(symbol: "circle.dotted", tone: .brand2, title: "Stick size", detail: "How far you slide the steering finger to walk at full speed.", names: size, selection: store.stepBinding("stickSize"))
                            Sep()
                            ChoiceRow(symbol: "arrow.left.and.right.square", title: "Steering area", detail: "How much of the left side of the screen steers.", names: zone, selection: store.stepBinding("moveZone"))
                            Sep()
                            ToggleRow(symbol: "figure.run", tone: .brand2, title: "Auto sprint", detail: "Push the stick forward to its edge and you sprint, without holding Run.", isOn: store.binding("autoSprint"))
                            Sep()
                            ToggleRow(symbol: "arrow.up.to.line", title: "Double tap to jump", detail: "Tap the world twice quickly to jump.", isOn: store.binding("doubleTapJump"))
                            Sep()
                            ChoiceRow(symbol: "timer", tone: .brand2, title: "Hold to mine", detail: "How long you hold a finger still before it starts mining.", names: hold, selection: store.stepBinding("holdTime"))
                        }
                        SectionLabel("Menus and inventory")
                        GlassGroup {
                            ChoiceRow(symbol: "hand.point.up.left.fill", title: "Menu touch", detail: "How far a finger can drift on a menu and still count as a tap.", names: menu, selection: store.stepBinding("menuTouch"))
                            Sep()
                            ToggleRow(symbol: "cursorarrow", tone: .brand2, title: "Cursor in inventory", detail: "Shows the cursor whenever an inventory is open.", isOn: store.binding("cursorInventory"))
                            Sep()
                            ChoiceRow(symbol: "speedometer", title: "Cursor speed", detail: "How far the cursor moves for each bit your finger travels.", names: look, selection: store.stepBinding("cursorSpeed"))
                            Sep()
                            ToggleRow(symbol: "eye.slash.fill", tone: .brand2, title: "Grey out unused settings", detail: "Greys out game settings that do nothing on an iPhone.", isOn: store.binding("greyUnused"))
                        }
                        SectionLabel("Performance")
                        GlassGroup {
                            ToggleRow(symbol: "bolt.heart.fill", title: "Auto Performance", detail: "Watches the memory iOS still lets the game use. When it runs short the game gives some back by capping far terrain, then render distance.",
                                      isOn: store.binding("autoPerformance"))
                            if store.bool("autoPerformance") {
                                Sep()
                                ChoiceRow(symbol: "clock.badge.exclamationmark", tone: .brand2, title: "Reacts", detail: "Early: while there is still room. Relaxed: only close to the limit.", names: reacts, selection: store.stepBinding("autoSensitivity"))
                                Sep()
                                ChoiceRow(symbol: "square.stack.3d.down.right", title: "Lowest distance", detail: "It never lowers the render distance below this.", names: distances, selection: store.stepBinding("autoMinDistance"))
                                Sep()
                                ToggleRow(symbol: "mountain.2.fill", tone: .brand2, title: "Cut far terrain", detail: "Shortens or turns off far terrain first: it costs the least picture.", isOn: store.binding("autoFarTerrain"))
                                Sep()
                                ToggleRow(symbol: "binoculars.fill", title: "Lower render distance", detail: "Two chunks at a time, down to the lowest distance. The biggest saving.", isOn: store.binding("autoRenderDistance"))
                                Sep()
                                ToggleRow(symbol: "aspectratio.fill", tone: .brand2, title: "Lower resolution", detail: "A last resort. It softens every pixel.", isOn: store.binding("autoResolution"))
                            }
                        }
                        SectionLabel("Calibration")
                        GlassGroup {
                            ChoiceRow(symbol: "arrow.left.and.right", title: "Touch shift X", detail: "Moves every touch sideways, in pixels. Use a negative value if your finger lands right of where it acts.", names: shift, selection: store.stepBinding("shiftX"))
                            Sep()
                            ChoiceRow(symbol: "arrow.up.and.down", tone: .brand2, title: "Touch shift Y", detail: "Moves every touch up or down. Use a negative value if your finger lands below where it acts.", names: shift, selection: store.stepBinding("shiftY"))
                            Sep()
                            ChoiceRow(symbol: "arrow.left.and.right.square", title: "Button shift X", detail: "Moves where the buttons answer, not how they are drawn.", names: shift, selection: store.stepBinding("buttonShiftX"))
                            Sep()
                            ChoiceRow(symbol: "arrow.up.and.down.square", tone: .brand2, title: "Button shift Y", detail: "Moves where the buttons answer, up or down.", names: shift, selection: store.stepBinding("buttonShiftY"))
                        }
                        Button(role: .destructive) { confirmReset = true } label: {
                            Text("Reset game settings").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .secondaryAction().tint(brand2).disabled(store.isDefault)
                        Text("These are the same settings as the game's iMC Settings page. Changes apply the next time the game starts.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.large)
        }
        .fullScreenCover(isPresented: $editing, onDismiss: { preview.objectWillChange.send(); reloadPreview() }) { TouchEditorScreen() }
        .onAppear { store.load(); reloadPreview() }
        .alert("Reset game settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Touch, menu and performance settings go back to what the game starts with. The button layout is kept.") }
        .alert("Reset the button layout?", isPresented: $confirmLayoutReset) {
            Button("Reset", role: .destructive) { preview.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every button goes back to the standard place.") }
    }

    private func reloadPreview() {
        let text = DiagFiles.text(TouchLayoutFile.path) ?? ""
        preview.slots = TouchLayoutFile.parse(text)
        preview.marginIndex = store.int("safeMargin")
    }

    private var layoutCard: some View {
        VStack(spacing: 14) {
            TouchCanvas(model: preview, interactive: false)
                .aspectRatio(TouchEditorScreen.deviceAspect, contentMode: .fit)
                .allowsHitTesting(false)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Button layout").font(.headline)
                    Text(preview.customised == 0 ? "The standard layout." : "\(preview.customised) button\(preview.customised == 1 ? "" : "s") moved or changed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Button { Haptics.tap(); editing = true } label: {
                    Label("Edit buttons", systemImage: "hand.draw.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .primaryAction().tint(brand)
                Button(role: .destructive) { confirmLayoutReset = true } label: {
                    Image(systemName: "arrow.counterclockwise").font(.headline).frame(width: 46, height: 46)
                }
                .secondaryAction().tint(brand2).disabled(preview.customised == 0)
                .accessibilityLabel("Reset the button layout")
            }
        }
        .padding(16).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 28, tint: brand.opacity(0.14))
    }
}
