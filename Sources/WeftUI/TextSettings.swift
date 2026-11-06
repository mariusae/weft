import SwiftUI
#if os(iOS)
import PhoneUI
#endif

/// How cards are set: a size for their words, and on the phone the face
/// of Prism's outline — kept on this device, chosen in Settings.
public enum TextSettings {
    public static let sizeKey = "WeftTextSize"

    #if os(macOS)
    public static let standardSize: Double = 14
    public static let sizes: ClosedRange<Double> = 11...22
    #else
    public static let standardSize: Double = 17
    public static let sizes: ClosedRange<Double> = 14...24
    #endif

    /// The size cards are written in: Settings', else the platform's own.
    public static var size: CGFloat {
        let stored = UserDefaults.standard.object(forKey: sizeKey) as? Double ?? standardSize
        return CGFloat(min(max(stored, sizes.lowerBound), sizes.upperBound))
    }

    /// The key the face is kept under — as Prism keeps its.
    public static let faceKey = "Typeface"

    #if os(iOS)
    /// Prism's faces that Weft has: the system's, and New York.
    public static let faces: [Typeface] = [.system, .apple]

    /// The outline's face, as Prism keeps it: under `Typeface`.
    public static var face: Typeface { faces.contains(Typeface.current) ? Typeface.current : .system }

    /// Whether what is written is set in New York.
    public static var serif: Bool { face == .apple }
    #else
    /// The faces offered, by the names Prism keeps them under: the
    /// system's, and Apple's New York.
    public static let faces: [(name: String, title: String)] = [("system", "System"), ("apple", "New York")]

    /// Whether what is written is set in New York.
    public static var serif: Bool { UserDefaults.standard.string(forKey: faceKey) == "apple" }
    #endif

    /// The face's design, for words set by SwiftUI: a card's title, a peek.
    public static var design: Font.Design { serif ? .serif : .default }

    /// What is written, at a size and weight, in the face chosen.
    public static func font(ofSize size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        let system = PlatformFont.systemFont(ofSize: size, weight: weight)
        guard serif, let serif = system.fontDescriptor.withDesign(.serif) else { return system }
        #if os(macOS)
        return PlatformFont(descriptor: serif, size: size) ?? system
        #else
        return PlatformFont(descriptor: serif, size: size)
        #endif
    }
}

/// Settings: the size of what is written — and, on the phone, its face and
/// the GitHub account, which the app gives as `account`.
public struct SettingsForm<Account: View>: View {
    @AppStorage(TextSettings.sizeKey) private var size = TextSettings.standardSize
    @AppStorage(WikiStore.spotlightKey) private var spotlight = true
    #if os(iOS)
    @AppStorage(TextSettings.faceKey) private var face = TextSettings.face.rawValue
    #else
    @AppStorage(TextSettings.faceKey) private var face = "system"
    #endif
    let account: Account

    public init(@ViewBuilder account: () -> Account) {
        self.account = account()
    }

    public var body: some View {
        Form {
            Section {
                Picker("Face", selection: $face) {
                    #if os(iOS)
                    ForEach(TextSettings.faces) { Text($0.title).tag($0.rawValue) }
                    #else
                    ForEach(TextSettings.faces, id: \.name) { Text($0.title).tag($0.name) }
                    #endif
                }
                LabeledContent("Size") {
                    Stepper(value: $size, in: TextSettings.sizes, step: 1) {
                        Text("\(Int(size)) pt").monospacedDigit()
                    }
                }
                Text("Words in a card are set like this.")
                    .font(.system(size: size, design: face == "apple" ? .serif : .default))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Text")
            }
            Section {
                Toggle("Show pages in system search", isOn: $spotlight)
                    .onChange(of: spotlight) { NotificationCenter.default.post(name: .weftSpotlightChanged, object: nil) }
            } header: {
                Text("Search")
            } footer: {
                Text("Pages are found in Spotlight by their titles, tags and words, and open here when chosen. Private notes never are.")
            }
            account
        }
        .formStyle(.grouped)
    }
}

extension SettingsForm where Account == EmptyView {
    public init() { self.init { EmptyView() } }
}
