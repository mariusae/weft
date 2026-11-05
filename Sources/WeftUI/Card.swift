import ReflectCore
import SwiftUI
import WeftCore

/// A tiddler's card in the river: its title and controls, then its page —
/// written in where it stands — and at its foot, what links to it.
struct Card: View {
    @Environment(WikiStore.self) private var store
    @Environment(River.self) private var river
    let title: String
    @State private var hovering = false
    @State private var confirmingDelete = false
    /// How many pages refer to it, counted when its deletion is asked for —
    /// not each time the card is drawn.
    @State private var referring = 0
    /// The title being typed in: renaming.
    @State private var renaming = false
    @FocusState private var titleFocused: Bool
    /// What of the title is selected as it is typed in: a new tiddler's, all of it.
    @State private var titleSelection: TextSelection?
    @State private var controller = EditorController()
    @State private var insertingQuery = false
    @State private var addingTag = false
    @State private var addingField = false
    @State private var definingFields = false
    @State private var historyShown = false
    @State private var addingRelated = false
    @State private var choosingIcon = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        let peeking = river.isFolded(title)
        VStack(alignment: .leading, spacing: peeking ? 0 : 14) {
            if peeking {
                peekRow
            } else {
                if showsHeader { header }
                relinking
                if store.needsReview(title) {
                    ConflictView(title: title)
                } else if let task = ringBeside {
                    // Untitled, a thing to do: its ring beside its first line, as a
                    // checklist's row has it — not a row of its own over it.
                    HStack(alignment: .top, spacing: 10) {
                        taskRing(task)
                            .padding(.top, TextSettings.size * 0.18)
                        CardEditor(title: title, controller: controller, addingTag: $addingTag,
                                   addingField: $addingField, addingRelated: $addingRelated, definingFields: $definingFields)
                    }
                } else {
                    CardEditor(title: title, controller: controller, addingTag: $addingTag,
                               addingField: $addingField, addingRelated: $addingRelated, definingFields: $definingFields)
                }
                let links = store.backlinks(of: title)
                if !links.isEmpty {
                    BacklinkFan(card: title, links: links)
                        .padding(.top, 4)
                }
            }
            // Its controls, out under it: on the phone, while it is open,
            // or asked for.
            if drawerShown {
                drawer
                    // Not dropping down: grown into place as the card opens to make room for it.
                    .transition(.asymmetric(insertion: .modifier(active: DrawerMorph(shown: false), identity: DrawerMorph(shown: true)),
                                            removal: .modifier(active: DrawerMorph(shown: false), identity: DrawerMorph(shown: true))))
            }
        }
        .animation(Self.drawerSpring, value: drawerShown)
        #if os(macOS)
        // No title: its controls and its fold in the corners, over its words.
        .overlay(alignment: .topTrailing) {
            if !peeking, !showsHeader { macControls.offset(y: -26) }
        }
        .overlay(alignment: .topLeading) {
            if !peeking, !showsHeader { foldChevron.offset(x: -23, y: -3) }
        }
        #endif
        .popover(isPresented: $choosingIcon) {
            IconPicker(current: store.icon(of: title)) { symbol in
                store.setIcon(symbol, of: title)
                choosingIcon = false
            }
        }
        .popover(isPresented: $insertingQuery) {
            QueryBuilder(query: Self.starterQuery, card: title) { query in
                insert(query)
                insertingQuery = false
            } cancel: {
                insertingQuery = false
            }
        }
        // Room round what it says: more at its foot, where the last line
        // would otherwise sit close against the edge.
        .padding(.horizontal, sizeClass == .compact ? 16 : 28)
        .padding(.top, peeking ? 12 : (sizeClass == .compact ? 16 : headerlessTop))
        .padding(.bottom, peeking ? 12 : (sizeClass == .compact ? 22 : 30))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Peeking: set back, a shade under an open card — to be read, not written in.
        .background {
            RoundedRectangle(cornerRadius: 14).fill(peeking ? Ink.paper.color : Color.card)
                #if os(iOS)
                // Written in: the card lit a little, as the drawer under it.
                .overlay { RoundedRectangle(cornerRadius: 14).fill(Ink.accent.color.opacity(river.isDrawerOut(title) ? 0.07 : 0)) }
                #endif
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.rule.color.opacity(river.isSelected(title) ? 0 : 1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.accent.color.opacity(river.isSelected(title) ? 0.45 : 0)))
        .shadow(color: .black.opacity(peeking ? 0.03 : 0.07), radius: peeking ? 4 : 10, y: peeking ? 1 : 3)
        #if os(iOS)
        // Swiped aside, its actions under it — not while it is written in.
        .cardSwipe(leading: leadingSwipe, trailing: trailingSwipe, enabled: !river.isWriting(title) && !renaming)
        #endif
        .onHover { hovering = $0 }
        // A click makes it the card ⌘↩ goes to.
        .simultaneousGesture(TapGesture().onEnded { river.select(title) })
        .sheet(isPresented: $historyShown) { HistorySheet(title: title).environment(store) }
        .confirmationDialog("Delete “\(store.shownTitle(title))”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { withAnimation { store.delete(title) } }
        } message: {
            Text(referring == 0 ? "Its file is removed; the graph's history keeps it."
                 : "\(referring) \(referring == 1 ? "page refers" : "pages refer") to it. Its file is removed; the graph's history keeps it.")
        }
        .environment(\.openURL, OpenURLAction { url in
            if let target = InlineMarkdown.title(from: url) {
                river.open(target, from: title)
                return .handled
            }
            return .systemAction
        })
        // A new tiddler's title is typed first.
        .onChange(of: river.wantsCaret(title) == .title, initial: true) { _, wanted in
            guard wanted else { return }
            startRenaming()
            river.caretTaken(title)
        }
        .onChange(of: titleFocused) { _, focused in
            if focused {
                river.caretEntered(title, in: .title)
            } else {
                renaming = false
                river.caretLeft(title, from: .title)
            }
        }
    }

    /// Peeking: its title in bold and what it says after, run on as one,
    /// set back and not to be written in — two lines on the Mac, three on
    /// the phone, always that room, so that a river of peeking cards is as
    /// tall as it looks. A tap opens it.
    @ViewBuilder private var peekRow: some View {
        let peek = store.peek(of: title)
        let task = store.taskState(title)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Its ring and its icon in its first line, not beside it: what
            // it says flows back under them to the card's edge.
            (peekLead(task: task)
             + Text(peek.title).bold().foregroundStyle(task == .done ? Ink.secondary.color : Ink.text.color)
             + Text(peek.summary.isEmpty ? "" : "  " + peek.summary).foregroundStyle(Ink.secondary.color))
                .strikethrough(false)
                .lineLimit(Self.peekLines, reservesSpace: true)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                #if os(iOS)
                // Tapped twice, opened and written in at once; once, opened to read.
                .gesture(TapGesture(count: 2).onEnded { writeAtOnce() }.exclusively(before: TapGesture().onEnded {
                    withAnimation(.snappy(duration: 0.22)) { river.toggleFold(title) }
                }))
                #else
                .onTapGesture { withAnimation(.snappy(duration: 0.22)) { river.toggleFold(title) } }
                #endif
                // The ring, first in the line, checked off where it is drawn.
                .overlay(alignment: .topLeading) {
                    if let task {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, task == .done ? .todo : .done) }
                        } label: {
                            Color.clear.frame(width: TextSettings.size * 1.4, height: TextSettings.size * 1.3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task == .done ? "Done" : "To do")
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the card")
            // Its first pictures, small, at the end of its lines: a page of
            // pictures alone shows what it is, peeking.
            let pictures = store.peekPictures(of: title)
            if !pictures.isEmpty {
                let side = (TextSettings.size * 1.3 * CGFloat(Self.peekLines)).rounded()
                HStack(spacing: 6) {
                    ForEach(pictures, id: \.self) { source in
                        PictureView(reference: ImageReference(source: source, width: Double(side * 2)), filling: side)
                            .frame(width: side, height: side)
                    }
                }
                .alignmentGuide(.firstTextBaseline) { $0[.top] + TextSettings.size }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy(duration: 0.22)) { river.toggleFold(title) } }
                .accessibilityHidden(true)
            }
            // Nothing at its end: on the phone, tapped it opens with its
            // controls, swiped it shows its actions, held its menu; on the
            // Mac, under the pointer its controls float over its end.
        }
        .font(.system(size: TextSettings.size))
        .draggingCard(title, shown: peek.title)
        #if os(iOS)
        // Held: what can be done with it, as a menu over it.
        .contextMenu { longPressMenu }
        #endif
        #if os(macOS)
        .overlay(alignment: .topLeading) { foldChevron.offset(x: -23, y: -3) }
        // Under the pointer, its controls over the end of its words, on a
        // fade of its own paper — taking no room from them otherwise.
        .overlay(alignment: .topTrailing) {
            if hovering {
                macControls
                    .padding(.leading, 28)
                    .background {
                        LinearGradient(stops: [.init(color: Ink.paper.color.opacity(0), location: 0),
                                               .init(color: Ink.paper.color, location: 0.35)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .offset(y: -3)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        #endif
    }

    /// What a peek's first line begins with: its ring, if it is a thing to
    /// do, then its icon — a day's calendar, or its own — as words are.
    private func peekLead(task: Tiddler.TaskState?) -> Text {
        var lead = Text("")
        if let task {
            lead = lead + Text(Image(systemName: task == .done ? "checkmark.circle.fill" : "circle"))
                .foregroundStyle(task == .done ? Ink.accent.color : Ink.secondary.color) + Text("  ")
        }
        if let symbol = shownSymbol {
            lead = lead + Text(Image(systemName: symbol)).foregroundStyle(Ink.secondary.color) + Text("  ")
        }
        return lead
    }

    #if os(iOS)
    /// Opened, and the caret put at the start of what it says.
    private func writeAtOnce() {
        withAnimation(.snappy(duration: 0.22)) {
            if river.isFolded(title) { river.toggleFold(title) }
            river.edit(title)
        }
    }

    /// Held on the phone: the actions most reached for, then the rest of its menu.
    @ViewBuilder private var longPressMenu: some View {
        Section {
            Button("Open in New River", systemImage: "plus.square.on.square") {
                river.openNew(River.State(graph: store.root?.path ?? "", cards: [title]))
            }
            if store.tiddler(title) != nil, store.kind(title) != .day {
                let pinned = store.isPinned(title), inbox = store.isInInbox(title)
                Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") { store.setPinned(title, !pinned) }
                Button(inbox ? "Done with It" : "Add to Inbox", systemImage: inbox ? "tray.and.arrow.up" : "tray.and.arrow.down") {
                    store.setInbox(title, !inbox)
                }
            }
            if canChooseIcon {
                Button("Choose Icon…", systemImage: store.icon(of: title) ?? "square.grid.3x3") { choosingIcon = true }
            }
            Button("Copy Link", systemImage: "link") { Platform.copy("[[\(title)]]") }
            ShareLink(item: (store.draft(title) ?? store.tiddler(title))?.text ?? store.shownTitle(title),
                      subject: Text(store.shownTitle(title))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Menu("More", systemImage: "ellipsis.circle") { menuItems }
    }

    /// Swiped from the left: what it is, moved on — a to-do checked off, or
    /// open again; out of the inbox; else made a to-do — and, inside that,
    /// the inbox, or a to-do, the other way.
    private var leadingSwipe: [SwipeAction] {
        guard store.kind(title) != .day, !store.isShadow(title), store.exists(title) || store.isEditing(title) else { return [] }
        let inbox = store.isInInbox(title)
        let inboxAction = inbox
            ? SwipeAction(name: "Out of Inbox", symbol: "tray.and.arrow.up", tint: .blue) { store.setInbox(title, false) }
            : SwipeAction(name: "Inbox", symbol: "tray.and.arrow.down", tint: .blue) { store.setInbox(title, true) }
        let toDo = SwipeAction(name: "To Do", symbol: "circle", tint: .orange) {
            withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, .todo) }
        }
        switch store.taskState(title) {
        case .todo:
            return [SwipeAction(name: "Done", symbol: "checkmark.circle.fill", tint: .green) {
                withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, .done) }
            }, inboxAction]
        case .done:
            return [toDo, inboxAction]
        case nil:
            return inbox ? [inboxAction, toDo] : [toDo, inboxAction]
        }
    }

    /// Swiped from the right: out of the river; inside that, deleted.
    private var trailingSwipe: [SwipeAction] {
        var actions = [SwipeAction(name: river.isQuery ? "Remove" : "Close", symbol: "xmark", tint: .gray) {
            withAnimation { river.close(title) }
        }]
        if store.tiddler(title) != nil, !store.isShadow(title) {
            actions.append(SwipeAction(name: "Delete", symbol: "trash", tint: .red) {
                referring = store.references(to: title).count
                confirmingDelete = true
            })
        }
        return actions
    }
    #endif

    /// How the card opens for its drawer, and the drawer grows into it.
    static let drawerSpring = Animation.spring(response: 0.34, dampingFraction: 0.82)

    #if os(macOS)
    static let peekLines = 2
    #else
    static let peekLines = 3
    #endif

    /// Being renamed: whether what refers to it is updated too.
    @ViewBuilder private var relinking: some View {
        if let draft = store.draftHead(title), store.tiddler(title) != nil, store.kind(title) != .day {
            let new = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if new != title, !new.isEmpty {
                let references = store.references(to: title)
                if !references.isEmpty {
                    Toggle(isOn: Binding(get: { store.relinkOnRename[title] ?? true }, set: { store.relinkOnRename[title] = $0 })) {
                        Text("Update \(references.count) \(references.count == 1 ? "tiddler" : "tiddlers") that refer to “\(store.shownTitle(title))”")
                            .help(references.prefix(12).joined(separator: ", "))
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// Which saved river the page calls its home — frontmatter `river:` —
    /// shown in its header, a tap bringing it back.
    @ViewBuilder private var homeRiverMenu: some View {
        let saved = store.savedRivers()
        let home = store.homeRiver(of: title)
        if !saved.isEmpty || home != nil {
            Menu("Home River", systemImage: RiverLink.symbol) {
                if let name = river.name, home != name {
                    Button("This River, “\(name)”") { store.setHomeRiver(name, of: title) }
                    Divider()
                }
                ForEach(saved, id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { home == name }, set: { store.setHomeRiver($0 ? name : nil, of: title) }))
                }
                if home != nil {
                    Divider()
                    Button("None") { store.setHomeRiver(nil, of: title) }
                }
            }
        }
    }

    /// What it shows before its title: its own icon, else a day's calendar.
    private var shownSymbol: String? {
        store.icon(of: title) ?? (store.kind(title) == .day ? "calendar" : nil)
    }

    private var canChooseIcon: Bool { !store.isShadow(title) }

    private var canRename: Bool { store.kind(title) != .day && !store.isShadow(title) }

    /// Whether it has no title yet — as it is being written, too.
    private var isUntitled: Bool { Untitled.isName(store.draftHead(title)?.title ?? title) }

    /// What an untitled card would be called: what it begins with, now.
    private var untitledSuggestion: String {
        Untitled.name(of: (store.draft(title) ?? store.tiddler(title))?.text ?? "") ?? ""
    }

    /// Whether it has a row for its title: not, untitled — its words are
    /// all there is of it, till it is given a title — but while one is
    /// typed, or with a home river to show.
    private var showsHeader: Bool {
        !isUntitled || renaming || homeElsewhere != nil
    }

    /// Untitled and a thing to do, with no title row: its ring, to go beside its words.
    private var ringBeside: Tiddler.TaskState? {
        showsHeader ? nil : store.taskState(title)
    }

    /// A thing to do's ring, to check it off — or open it again.
    private func taskRing(_ task: Tiddler.TaskState) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { store.setTaskState(title, task == .done ? .todo : .done) }
        } label: {
            Image(systemName: task == .done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(task == .done ? Color.white : Ink.secondary.color, Ink.accent.color)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(task == .done ? "Done — click to open again" : "To do — click when done")
        .accessibilityLabel(task == .done ? "Done" : "To do")
    }

    /// Its home river, when that is not this one.
    private var homeElsewhere: String? {
        guard let home = store.homeRiver(of: title), home.caseInsensitiveCompare(river.name ?? "") != .orderedSame else { return nil }
        return home
    }

    /// Room over what it says: on the Mac, with no title row, enough for
    /// its controls to stand in.
    private var headerlessTop: CGFloat {
        #if os(macOS)
        showsHeader ? 22 : 34
        #else
        22
        #endif
    }

    /// Whether its drawer of controls is out under it: on the phone, while
    /// it is open, always; peeking, when its ⋯ is tapped. The Mac's are
    /// over it.
    private var drawerShown: Bool {
        #if os(macOS)
        false
        #else
        !river.isFolded(title) || river.isDrawerOut(title)
        #endif
    }

    /// Its title taken away: untitled again, shown as it begins, what
    /// referred to it following it.
    private func removeTitle() {
        river.change(title, settling: true) { $0.title = "" }
    }

    private func startRenaming() {
        guard canRename else { return }
        renaming = true
        titleFocused = true
        Task { @MainActor in
            // Asked again until the field has the keys: a card just opened
            // out of view is laid out only as the river scrolls to it.
            for _ in 0..<20 where !titleFocused {
                try? await Task.sleep(for: .milliseconds(50))
                if renaming, !titleFocused { titleFocused = true }
            }
            // A new tiddler's made-up name, all selected: typed over at once —
            // once the field has taken the keys, which puts the caret at its end.
            guard titleFocused, !store.exists(title), !isUntitled else { return }
            try? await Task.sleep(for: .milliseconds(30))
            let name = store.draftHead(title)?.title ?? title
            titleSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    /// The title on one line — running on under the controls, which float
    /// over it on glass, and cut off at the card's edge — and the controls.
    /// Double-clicked, it is typed in.
    private var header: some View {
        let kind = store.kind(title)
        let shown = store.draftHead(title).map(\.title).flatMap { Untitled.isName($0) ? nil : $0 } ?? store.shownTitle(title)
        let task = store.taskState(title)
        let peeking = river.isFolded(title)
        return HStack(alignment: .center, spacing: peeking ? 8 : 10) {
            // Its icon — a day's calendar, or its own — a click away from another.
            if let symbol = shownSymbol {
                Button { if canChooseIcon { choosingIcon = true } } label: {
                    Image(systemName: symbol)
                        .foregroundStyle(Ink.secondary.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(kind == .day && store.icon(of: title) == nil ? "A day" : "Its icon: \(PageIcon.name(of: symbol)) — click to choose another")
                .accessibilityLabel(PageIcon.name(of: symbol))
            }
            // A page that is a thing to do: its ring, to check it off.
            if let task { taskRing(task) }
            if renaming {
                // Untitled: empty, what it begins with offered — taken with
                // Return, typed over, or left, and it stays untitled.
                TextField(isUntitled ? (untitledSuggestion.isEmpty ? "Title" : untitledSuggestion) : "Title", text: Binding {
                    let name = store.draftHead(title)?.title ?? title
                    return Untitled.isName(name) ? "" : name
                } set: { value in
                    store.change(title) { $0.title = value.isEmpty && Untitled.isName(title) ? title : value }
                }, selection: $titleSelection)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .focused($titleFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit {
                    // Untitled, and nothing typed: called what it begins with.
                    if isUntitled, case let offered = untitledSuggestion, !offered.isEmpty {
                        store.change(title) { $0.title = offered }
                    }
                    // A new tiddler named: on to what it says. One renamed: done.
                    if store.exists(title) { Platform.endEditing() } else { river.edit(title) }
                }
            } else if isUntitled {
                // No title till one is given: its ring, or its home river, alone.
                EmptyView()
            } else {
                Text(peeking ? store.peek(of: title).title : shown)
                    // Peeking: the size of what it says, bold.
                    .font(peeking ? .system(size: TextSettings.size, weight: .bold) : .system(size: 22, weight: .semibold))
                    .italic(!store.exists(title) && !store.isEditing(title))
                    // Done: struck through, quieter.
                    .strikethrough(task == .done, color: Ink.secondary.color)
                    .foregroundStyle((store.exists(title) || store.isEditing(title)) && task != .done ? Ink.text.color : Ink.secondary.color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    #if os(macOS)
                    .onTapGesture(count: 2) { startRenaming() }
                    #else
                    // A tap folds it to its title, or opens it again; renaming is in its menu.
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy(duration: 0.22)) { river.toggleFold(title) } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(river.isFolded(title) ? "Unfolds the card" : "Folds the card to its title")
                    #endif
            }
            let wiki = store.draftHead(title)?.isWiki ?? (kind == .wiki)
            if wiki, !isUntitled {
                Label("Wiki", systemImage: "book.closed")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(Ink.accent.color)
                    .background(Ink.accent.color.opacity(0.1), in: Capsule())
                    .fixedSize()
                    .help("A wiki page: canonical, kept up")
            }
            // Its home river, a tap away — but in it already.
            if let home = homeElsewhere {
                Button { river.follow(river: home) } label: {
                    Label(home, systemImage: store.savedRiverIcon(home) ?? RiverLink.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(store.savedRiverName(home) == nil ? Ink.secondary.color : Ink.accent.color)
                        .background(Ink.accent.color.opacity(0.1), in: Capsule())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help("Its home river: bring back “\(home)”")
                .contextMenu {
                    Button("Remove Home River", systemImage: "minus.circle") { store.setHomeRiver(nil, of: title) }
                }
            }
        }
        // As wide as the card gives, however long the title: the rest of it
        // cut off before the controls.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .clipped()
        // Dragged by its title to elsewhere in the river; on the phone, held first.
        .draggingCard(title, shown: shown, enabled: !renaming)
        #if os(iOS)
        // Held by its title: what can be done with it, as a menu over it.
        .contextMenu { if !renaming { longPressMenu } }
        #endif
        #if os(macOS)
        // In the margin before the title: fold or unfold — ⌥, every card.
        // Over the drag, not in it: its shape, the title's, would take the
        // chevron's clicks from it, outside it as it is.
        .overlay(alignment: .leading) { foldChevron.offset(x: -23) }
        .safeAreaInset(edge: .trailing, spacing: 8) { macControls }
        #endif
    }

    #if os(macOS)
    /// The card's disclosure triangle: faint under the pointer, there always
    /// when folded; ⌥-clicked, every card folded or opened as this one goes.
    private var foldChevron: some View {
        let folded = river.isFolded(title)
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                if NSEvent.modifierFlags.contains(.option) {
                    if folded { river.unfoldAll() } else { river.foldAll() }
                } else {
                    river.toggleFold(title)
                }
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .rotationEffect(.degrees(folded ? 0 : 90))
                .frame(width: 18, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Ink.secondary.color)
        .opacity(folded ? 0.9 : hovering ? 0.6 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(folded ? "Unfold (⌃⌘↓) — ⌥-click unfolds every card" : "Fold to its title (⌃⌘↑) — ⌥-click folds every card")
        .accessibilityLabel(folded ? "Unfold" : "Fold")
    }
    #endif

    #if os(macOS)
    /// The card's controls, at the end of its title row: under the pointer,
    /// faint while it is written in or chosen, else out of sight. Open:
    /// text or outline, the days beside a day's, what a query river does
    /// with it, More, and closing it. Peeking: More and closing.
    private var macControls: some View {
        let peeking = river.isFolded(title)
        let shownMode = store.editorMode(title)
        return HStack(spacing: 2) {
            if !peeking {
                HStack(spacing: 1) {
                    ForEach(WikiStore.EditorMode.allCases, id: \.self) { mode in
                        Button { store.setEditorMode(mode, for: title) } label: {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 26, height: 20)
                                .background(mode == shownMode ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 5))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(mode == shownMode ? Ink.text.color : Ink.secondary.color)
                        .accessibilityLabel(mode.rawValue)
                        .accessibilityAddTraits(mode == shownMode ? .isSelected : [])
                    }
                }
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Ink.rule.color))
                .help("Write as text, or as an outline of rows")
                .padding(.trailing, 6)
                if store.kind(title) == .day {
                    CardButton("The Day Before", "chevron.left") { withAnimation(.snappy(duration: 0.28)) { river.openDay(beside: title, by: -1) } }
                    CardButton("The Day After", "chevron.right") { withAnimation(.snappy(duration: 0.28)) { river.openDay(beside: title, by: 1) } }
                }
                // Its pages to read: the reader beside the river, a click away.
                if store.canRead(title) {
                    CardButton("Read", "doc.richtext") { river.reading = title }
                }
                if river.isQuery {
                    if river.isHeld(title) {
                        CardButton("Release to Query", "arrow.uturn.down") { withAnimation { river.releaseToQuery(title) } }
                    } else {
                        CardButton("Keep at Top", "pin") { withAnimation { river.keepAtTop(title) } }
                    }
                }
            }
            Menu { menuItems } label: { CardButtonFace(symbol: "ellipsis") }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More")
            CardButton(river.isQuery ? "Remove from River" : "Close", "xmark") { withAnimation { river.close(title) } }
        }
        .foregroundStyle(Ink.secondary.color)
        .opacity(hovering ? 1 : !peeking && (river.isWriting(title) || river.isSelected(title)) ? 0.45 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
    #endif

    /// The card's controls, slid out under it: open or peek, text or
    /// outline, the days beside a day's, what a query river does with it,
    /// the rest of what can be done with it, and closing it.
    private var drawer: some View {
        let peeking = river.isFolded(title)
        let mode = store.editorMode(title)
        let other: WikiStore.EditorMode = mode == .text ? .outline : .text
        return HStack(spacing: 0) {
            DrawerButton(peeking ? "Open" : "Peek",
                         peeking ? "arrow.up.left.and.arrow.down.right.circle" : "arrow.down.right.and.arrow.up.left.circle") {
                withAnimation(.snappy(duration: 0.22)) { river.toggleFold(title) }
            }
            DrawerButton("Write as \(other.rawValue)", other == .outline ? "list.bullet.circle" : "line.3.horizontal.circle") {
                store.setEditorMode(other, for: title)
            }
            // Its pages to read: the reader, back again, a tap away.
            if store.canRead(title) {
                DrawerButton("Read", "doc.richtext") { river.reading = title }
            }
            if store.kind(title) == .day {
                DrawerButton("The Day Before", "chevron.backward.circle") { withAnimation(.snappy(duration: 0.28)) { river.openDay(beside: title, by: -1) } }
                DrawerButton("The Day After", "chevron.forward.circle") { withAnimation(.snappy(duration: 0.28)) { river.openDay(beside: title, by: 1) } }
            }
            if river.isQuery {
                if river.isHeld(title) {
                    DrawerButton("Release to Query", "arrow.uturn.down.circle") { withAnimation { river.releaseToQuery(title) } }
                } else {
                    DrawerButton("Keep at Top", "pin.circle") { withAnimation { river.keepAtTop(title) } }
                }
            }
            Menu { menuItems } label: { DrawerIcon(symbol: "ellipsis.circle") }
                #if os(macOS)
                .menuStyle(.button)
                #endif
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity)
                .help("More")
                .accessibilityLabel("More")
            DrawerButton(river.isQuery ? "Remove from River" : "Close", "xmark.circle") {
                withAnimation { river.close(title) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .background(Ink.drawer.color, in: Capsule())
        .padding(.top, 12)
    }

    /// Everything else to do with the card: in its drawer's More.
    @ViewBuilder private var menuItems: some View {
        if canRename {
            if isUntitled {
                // What it begins with, as its title: at once.
                // As last saved: the menu not drawn again with each letter typed.
                if let name = store.untitledName(title), name != "Untitled" {
                    Button("Title “\(name)”", systemImage: "arrow.up.to.line") { river.titleByFirstLine(title) }
                }
                Button("Add Title…", systemImage: "character.cursor.ibeam") { startRenaming() }
            } else {
                Button("Rename", systemImage: "character.cursor.ibeam") { startRenaming() }
                Button("Remove Title", systemImage: "minus.circle") { removeTitle() }
            }
        }
        Button(river.isFolded(title) ? "Unfold" : "Fold") {
            withAnimation(.snappy(duration: 0.2)) { river.toggleFold(title) }
        }
        if river.isQuery {
            // What the river finds: held at its top; what is held, let go.
            if river.isHeld(title) {
                Button("Release to Query", systemImage: "arrow.uturn.down") { withAnimation { river.releaseToQuery(title) } }
            } else {
                Button("Keep at Top", systemImage: "pin") { withAnimation { river.keepAtTop(title) } }
            }
            Button("Remove from River", systemImage: "minus.circle") { withAnimation { river.close(title) } }
        } else {
            Button("Close Other Cards") { withAnimation { river.closeOthers(title) } }
        }
        #if os(iOS)
        // The Mac's switch in the header, on the phone in here: no room beside the title.
        Picker("Write As", selection: Binding(get: { store.editorMode(title) }, set: { store.setEditorMode($0, for: title) })) {
            ForEach(WikiStore.EditorMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
        }
        #endif
        Divider()
        if canChooseIcon {
            Button("Choose Icon…", systemImage: store.icon(of: title) ?? "square.grid.3x3") { choosingIcon = true }
            if store.icon(of: title) != nil {
                Button("Remove Icon", systemImage: "minus.circle") { store.setIcon(nil, of: title) }
            }
        }
        Button("Add Tag", systemImage: "tag") { addingTag = true }
        Button("Relate To…", systemImage: "link") { addingRelated = true }
        homeRiverMenu
        Button("Add Field", systemImage: "plus.rectangle") {
            addingField = true
            store.fieldsShown.insert(title)
        }
        Button("Insert Query…", systemImage: "line.3.horizontal.decrease.circle") { insertingQuery = true }
        if store.tiddler(title) != nil, !store.tagged(title).isEmpty || !FieldSpec.specs(of: store.tiddler(title)!).isEmpty {
            Button("Fields of Tiddlers Tagged “\(title)”…", systemImage: "list.bullet.rectangle") { definingFields = true }
        }
        if store.tiddler(title) != nil || store.isEditing(title) {
            let wiki = store.draftHead(title)?.isWiki ?? store.isWiki(title)
            Button(wiki ? "Remove from Wiki" : "Add to Wiki") { store.setWiki(title, !wiki) }
        }
        if store.tiddler(title) != nil, store.kind(title) != .day {
            // Prism's flags: in its inbox, among its pinned.
            let inbox = store.isInInbox(title), pinned = store.isPinned(title)
            Button(inbox ? "Done with It" : "Add to Inbox", systemImage: inbox ? "tray.and.arrow.up" : "tray.and.arrow.down") {
                store.setInbox(title, !inbox)
            }
            Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") { store.setPinned(title, !pinned) }
        }
        if store.canRead(title) {
            Button("Read", systemImage: "doc.richtext") { river.reading = title }
        }
        if store.kind(title) != .day, !store.isShadow(title) {
            // The page itself a thing to do: checked off on its card, listed in Tasks.
            switch store.taskState(title) {
            case nil:
                Button("Make a To-Do", systemImage: "circle") { store.setTaskState(title, .todo) }
            case .todo:
                Button("Mark Done", systemImage: "checkmark.circle") { store.setTaskState(title, .done) }
                Button("No Longer a To-Do", systemImage: "circle.slash") { store.setTaskState(title, nil) }
            case .done:
                Button("Mark Not Done", systemImage: "circle") { store.setTaskState(title, .todo) }
                Button("No Longer a To-Do", systemImage: "circle.slash") { store.setTaskState(title, nil) }
            }
        }
        Divider()
        Button("Find in Card", systemImage: "text.magnifyingglass") { river.find(in: title) }
        if store.tiddler(title) != nil {
            Button("History…", systemImage: "clock.arrow.circlepath") { historyShown = true }
        }
        Button("Copy Link") { Platform.copy("[[\(title)]]") }
        // What it says, as written — the draft, while it is being written.
        Button("Copy Contents", systemImage: "doc.on.doc") {
            Platform.copy((store.draft(title) ?? store.tiddler(title))?.text ?? "")
        }
        .disabled(store.tiddler(title) == nil && !store.isEditing(title))
        if Platform.canReveal, let path = store.path(of: title) {
            Button("Show in Finder") { Platform.reveal(path) }
        }
        if store.tiddler(title) != nil, !store.isShadow(title) {
            Divider()
            Button("Delete Tiddler…", role: .destructive) {
                referring = store.references(to: title).count
                confirmingDelete = true
            }
        }
    }

    /// A query put in: at the caret, while the caret is in the text; else at
    /// the foot of what the card says.
    private func insert(_ query: Query) {
        if river.isWriting(title), store.editorMode(title) == .text {
            controller.insertBlock(query.block)
        } else {
            river.change(title, settling: true) { page in
                let text = page.text
                page.text += (text.isEmpty || text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n") + query.block + "\n"
            }
        }
    }

    /// What a new query starts as: what is tagged with this tiddler.
    private static var starterQuery: Query {
        var query = Query()
        query.tags = [Query.this]
        return query
    }
}

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(Ink.accent.color)
            .background(Ink.accent.color.opacity(0.12), in: Capsule())
    }
}

/// Views laid out in rows, wrapping, as words are.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

#if os(macOS)
/// One of a card's controls on the Mac: a plain symbol, lit under the
/// pointer as a toolbar's buttons are.
private struct CardButton: View {
    let name: String
    let symbol: String
    let action: () -> Void

    init(_ name: String, _ symbol: String, action: @escaping () -> Void) {
        self.name = name
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) { CardButtonFace(symbol: symbol) }
            .buttonStyle(.plain)
            .help(name)
            .accessibilityLabel(name)
    }
}

private struct CardButtonFace: View {
    let symbol: String
    @State private var hovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 26, height: 24)
            .background(Color.primary.opacity(hovered ? 0.08 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onHover { hovered = $0 }
    }
}
#endif

/// One of a card's controls in its drawer: its symbol alone, white on
/// the drawer's colour — its name said under the pointer, and aloud.
private struct DrawerButton: View {
    let name: String
    let symbol: String
    let action: () -> Void

    init(_ name: String, _ symbol: String, action: @escaping () -> Void) {
        self.name = name
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) { DrawerIcon(symbol: symbol) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help(name)
            .accessibilityLabel(name)
    }
}

private struct DrawerIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
    }
}

/// A drawer coming or going: a narrow, soft pill swelling to its full
/// width and sharpening, its icons with it — morphing into place.
private struct DrawerMorph: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: shown ? 1 : 0.35, y: shown ? 1 : 0.7, anchor: .center)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
    }
}
