import SwiftUI
import WeftCore

/// The fields a tiddler's tags give it, shown by kind: a date as a date —
/// a link to its day in Reflect — a link as a link, a web address opening,
/// a choice as a pill, yes or no as a mark.
struct PropertiesView: View {
    @Environment(WikiStore.self) private var store
    let tiddler: Tiddler
    let specs: [FieldSpec]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(specs, id: \.name) { spec in
                GridRow {
                    Text(spec.name)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    value(spec, tiddler[field: spec.name]?.text ?? tiddler[field: spec.name]?.list?.joined(separator: ", ") ?? "")
                }
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func value(_ spec: FieldSpec, _ text: String) -> some View {
        TypedValue(spec: spec, text: text)
    }
}

/// A field's value, shown by its kind.
struct TypedValue: View {
    let spec: FieldSpec
    let text: String

    var body: some View {
        value(spec, text)
    }

    @ViewBuilder private func value(_ spec: FieldSpec, _ text: String) -> some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            switch spec.kind {
            case .date:
                if let date = FieldSpec.date(text) {
                    TiddlerLink(title: text, shown: date.formatted(date: .long, time: .omitted))
                } else {
                    Text(text)
                }
            case .link:
                TiddlerLink(title: text)
            case .url:
                if let url = URL(string: text.contains("://") ? text : "https://" + text) {
                    Link(text, destination: url)
                } else {
                    Text(text)
                }
            case .flag:
                Image(systemName: FieldSpec.flag(text) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(FieldSpec.flag(text) ? Color.accentColor : .secondary)
            case .choice:
                Text(text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            case .number:
                Text(text).monospacedDigit()
            case .text:
                InlineText(text: text)
            }
        }
    }
}

/// A typed field in the editor: a date picker, a menu of choices, a
/// toggle, a field offering titles for a link.
struct TypedFieldEditor: View {
    @Environment(WikiStore.self) private var store
    let spec: FieldSpec
    @Binding var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(spec.name).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
            control
        }
    }

    @ViewBuilder private var control: some View {
        switch spec.kind {
        case .date:
            HStack {
                if let date = FieldSpec.date(value) {
                    DatePicker("", selection: Binding(get: { date }, set: { value = FieldSpec.value(of: $0) }),
                               displayedComponents: .date)
                        .labelsHidden()
                    Button { value = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Clear")
                } else {
                    Button("Set Date") { value = FieldSpec.value(of: Date()) }
                }
                Spacer()
            }
        case .flag:
            HStack {
                Toggle("", isOn: Binding(get: { FieldSpec.flag(value) }, set: { value = $0 ? "yes" : "no" }))
                    .labelsHidden()
                Spacer()
            }
        case .choice(let options):
            HStack {
                Picker("", selection: $value) {
                    Text("None").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    if !value.isEmpty && !options.contains(value) { Text(value).tag(value) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                TextField("A tiddler or note", text: $value)
                    .textFieldStyle(.roundedBorder)
                let suggestions = value.isEmpty || store.exists(value) ? [] : completions(for: value, among: store.titles, limit: 6)
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(suggestions, id: \.self) { title in
                            Button(title) { value = title }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        case .number:
            TextField("0", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        case .url:
            TextField("https://", text: $value)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
        case .text:
            TextField("", text: $value).textFieldStyle(.roundedBorder)
        }
    }
}

/// A tag tiddler's own `fields`: the fields every tiddler tagged with it
/// has, each a name and a kind.
struct SchemaEditor: View {
    let tag: String
    @Binding var specs: [FieldSpec]
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tiddlers tagged “\(tag)” have")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(Array(specs.enumerated()), id: \.offset) { index, spec in
                HStack {
                    TextField("Name", text: Binding(get: { specs[index].name }, set: { specs[index].name = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                    Picker("", selection: Binding(get: { Self.kindTag(spec.kind) }, set: { specs[index].kind = Self.kind($0, from: spec.kind) })) {
                        ForEach(FieldSpec.Kind.simple, id: \.self) { Text($0.label).tag(Self.kindTag($0)) }
                        Text("Choice").tag("choice")
                    }
                    .labelsHidden()
                    .fixedSize()
                    if case .choice(let options) = spec.kind {
                        TextField("Choices, separated by |", text: Binding(
                            get: { options.joined(separator: " | ") },
                            set: { specs[index].kind = .choice($0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    Spacer(minLength: 0)
                    Button { specs.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove field")
                }
            }
            HStack {
                TextField("Add a field", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, !specs.contains(where: { $0.name == name }) else { return }
        specs.append(FieldSpec(name: name))
        newName = ""
    }

    private static func kindTag(_ kind: FieldSpec.Kind) -> String {
        if case .choice = kind { return "choice" }
        return kind.label
    }

    private static func kind(_ tag: String, from current: FieldSpec.Kind) -> FieldSpec.Kind {
        if tag == "choice" {
            if case .choice = current { return current }
            return .choice([])
        }
        return FieldSpec.Kind.simple.first { $0.label == tag } ?? .text
    }
}
