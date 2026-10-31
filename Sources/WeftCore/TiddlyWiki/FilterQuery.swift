import Foundation

extension Query {
    /// The query a TiddlyWiki filter asks, when it asks one weft can: a
    /// single run — `[tag[Fruit]!tag[Soft]sort[modified]limit[5]]` — of
    /// steps weft has a condition for. Nil for any other.
    public init?(tiddlyWikiFilter filter: String, show: Display = .list) {
        self.init()
        self.show = show
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), let steps = Self.steps(String(trimmed.dropFirst().dropLast())) else {
            return nil
        }
        // The title steps such as `tagging[]` and `backlinks[]` start from.
        var source: String?
        for step in steps {
            let value: String?
            switch step.parameter {
            case .literal(let text): value = text
            case .variable(let name): value = ["currentTiddler", "storyTiddler"].contains(name) ? Self.this : nil
            case .reference(let reference): value = reference == "!!title" ? Self.this : nil
            case .none: value = nil
            }
            switch (step.negated, step.operator) {
            case (false, "all") where value == "current", (false, "is") where value == "current":
                source = Self.this
            case (false, "all"), (true, "is") where value == "system" || value == "draft", (true, "has") where value == "draft.of":
                continue
            case (false, "title"), (false, ""):
                guard let value else { return nil }
                source = value
            case (false, "tag"):
                guard let value else { return nil }
                tags.append(value)
            case (true, "tag"):
                guard let value else { return nil }
                excludedTags.append(value)
            case (false, "tagging"):
                guard let source else { return nil }
                tags.append(source)
            case (false, "backlinks"):
                guard let source else { return nil }
                linksTo = source
            case (false, "links"):
                guard let source else { return nil }
                linkedFrom = source
            case (false, "list"):
                guard let value else { return nil }
                listedIn = value
            case (false, "enlist") where step.referenceList != nil:
                listedIn = step.referenceList!
            case (_, "sort"), (_, "nsort"), (_, "sortan"), (_, "sortcs"), (_, "nsortcs"):
                sort = Sort(rawValue: value ?? "title") ?? .title
                descending = step.negated
            case (false, "limit"), (false, "first"):
                guard let value, let number = Int(value) else { return nil }
                limit = number
            case (false, "search"):
                guard let value else { return nil }
                if step.suffix == "title" { titleContains = value } else { textContains = value }
            case (false, "has"):
                guard let value else { return nil }
                hasFields.append(value)
            default:
                return nil
            }
        }
        // A filter that only names a title, or only asks for everything, is
        // no question worth a query.
        if tags.isEmpty, excludedTags.isEmpty, linksTo.isEmpty, linkedFrom.isEmpty, listedIn.isEmpty,
           titleContains.isEmpty, textContains.isEmpty, hasFields.isEmpty, limit == nil, sort == .automatic {
            return nil
        }
    }

    struct Step {
        var negated: Bool
        var `operator`: String
        var suffix: String?
        var parameter: Parameter

        enum Parameter {
            case literal(String), variable(String), reference(String), none
        }

        /// `X` in `enlist{X!!list}`.
        var referenceList: String? {
            guard case .reference(let reference) = parameter, reference.hasSuffix("!!list") else { return nil }
            let title = String(reference.dropLast(6))
            return title.isEmpty ? Query.this : title
        }
    }

    /// A run's steps: `!tag[x]`, `sort:title[]`, `tag<currentTiddler>`, `[Title]`.
    static func steps(_ run: String) -> [Step]? {
        var steps: [Step] = []
        var characters = Substring(run)
        while !characters.isEmpty {
            var negated = false
            if characters.first == "!" {
                negated = true
                characters = characters.dropFirst()
            }
            let name = characters.prefix { !"[{<".contains($0) }
            characters = characters.dropFirst(name.count)
            guard let open = characters.first else { return nil }
            let close: Character = open == "[" ? "]" : open == "{" ? "}" : ">"
            guard let end = characters.dropFirst().firstIndex(of: close) else { return nil }
            let value = String(characters[characters.index(after: characters.startIndex)..<end])
            characters = characters[characters.index(after: end)...]
            let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
            let parameter: Step.Parameter = open == "[" ? .literal(value) : open == "<" ? .variable(value) : .reference(value)
            steps.append(Step(negated: negated, operator: parts.first ?? "", suffix: parts.count > 1 ? parts[1] : nil,
                              parameter: value.isEmpty && open == "[" ? .none : parameter))
        }
        return steps
    }
}
