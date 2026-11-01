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

    #if os(iOS)
    /// Prism's faces that Weft has: the system's, and New York.
    public static let faces: [Typeface] = [.system, .apple]

    /// The outline's face, as Prism keeps it: under `Typeface`.
    public static var face: Typeface { faces.contains(Typeface.current) ? Typeface.current : .system }
    #endif
}

/// Settings: the size of what is written — and, on the phone, its face and
/// the GitHub account, which the app gives as `account`.
public struct SettingsForm<Account: View>: View {
    @AppStorage(TextSettings.sizeKey) private var size = TextSettings.standardSize
    #if os(iOS)
    @AppStorage("Typeface") private var face = TextSettings.face.rawValue
    #endif
    let account: Account

    public init(@ViewBuilder account: () -> Account) {
        self.account = account()
    }

    public var body: some View {
        Form {
            Section {
                #if os(iOS)
                Picker("Face", selection: $face) {
                    ForEach(TextSettings.faces) { Text($0.title).tag($0.rawValue) }
                }
                #endif
                LabeledContent("Size") {
                    Stepper(value: $size, in: TextSettings.sizes, step: 1) {
                        Text("\(Int(size)) pt").monospacedDigit()
                    }
                }
                Text("Words in a card are set like this.")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Text")
            }
            account
        }
        .formStyle(.grouped)
    }
}

extension SettingsForm where Account == EmptyView {
    public init() { self.init { EmptyView() } }
}
