import Foundation
import NaturalLanguage

// MARK: - PHIRedactor

/// Best-effort scrub of person identifiers from transcript/body text before
/// it is handed to a language model, per CARECIRCLE_SPEC §5.4.
///
/// This is a layered heuristic, **not** a guarantee. Four passes run in
/// order, each strictly more general than the last:
///
/// 1. **Known names** — the recipient's and caregivers' stored names, plus
///    common diminutives of their first names (so "Robert" also catches
///    "Bob"/"Bobby"), longest match first so full names collapse to one token.
/// 2. **Relationship terms** — "Mom"/"Grandpa"/etc., which in a caregiving
///    transcript almost always denote the care recipient, mapped to
///    `[RECIPIENT]`.
/// 3. **On-device NER** — `NLTagger`'s personal-name tagger catches names the
///    known list missed: other people, and misspelled or speech-recognition-
///    mangled tokens that still read as names. These become `[NAME]`.
///
/// Misspellings and ASR errors are handled only insofar as the NER pass still
/// recognises them as name-like; an arbitrary typo of a known name can slip
/// through. Treat the output as reduced-exposure, not anonymised, and keep
/// the cloud fallback gated on the user's on-device-AI availability.
nonisolated struct PHIRedactor: Sendable {
    static let recipientPlaceholder = "[RECIPIENT]"
    static let caregiverPlaceholderPrefix = "[CAREGIVER_"
    static let genericNamePlaceholder = "[NAME]"

    let recipientFirstName: String?
    let recipientLastName: String?
    let caregiverDisplayNames: [String]

    init(
        recipientFirstName: String? = nil,
        recipientLastName: String? = nil,
        caregiverDisplayNames: [String] = []
    ) {
        self.recipientFirstName = recipientFirstName
        self.recipientLastName = recipientLastName
        self.caregiverDisplayNames = caregiverDisplayNames
    }

    init(circle: Circle, currentCaregiverDisplayName: String?) {
        let recipient = circle.careRecipient
        var caregivers: [String] = circle.members
            .map(\.displayName)
            .filter { !$0.isEmpty }
        if let current = currentCaregiverDisplayName, !current.isEmpty {
            caregivers.append(current)
        }
        self.init(
            recipientFirstName: recipient?.firstName,
            recipientLastName: recipient?.lastName,
            caregiverDisplayNames: Array(Set(caregivers))
        )
    }

    func redact(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var output = input

        // Longest tokens first so "Jane Doe" collapses to a single
        // placeholder rather than "[RECIPIENT] [RECIPIENT]".
        for token in recipientTokens().sorted(by: { $0.count > $1.count }) {
            output = replace(token: token, in: output, with: Self.recipientPlaceholder)
        }

        for (offset, name) in caregiverDisplayNames.enumerated() {
            let placeholder = "\(Self.caregiverPlaceholderPrefix)\(offset + 1)]"
            for token in tokens(for: name).sorted(by: { $0.count > $1.count }) {
                output = replace(token: token, in: output, with: placeholder)
            }
        }

        for term in Self.recipientRelationshipTerms {
            output = replace(token: term, in: output, with: Self.recipientPlaceholder)
        }

        return redactPersonalNames(in: output)
    }

    // MARK: - Known-name tokens

    private func recipientTokens() -> [String] {
        var tokens = Set<String>()
        let first = recipientFirstName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = recipientLastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first, !first.isEmpty {
            tokens.insert(first)
            tokens.formUnion(Self.nicknameVariants(of: first))
        }
        if let last, !last.isEmpty {
            tokens.insert(last)
        }
        if let first, let last, !first.isEmpty, !last.isEmpty {
            tokens.insert("\(first) \(last)")
        }
        return Array(tokens)
    }

    private func tokens(for displayName: String) -> [String] {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parts = trimmed.split(separator: " ").map(String.init)
        var tokens = Set<String>([trimmed])
        tokens.formUnion(parts.filter { $0.count >= 3 })
        if let first = parts.first {
            tokens.formUnion(Self.nicknameVariants(of: first))
        }
        return Array(tokens)
    }

    /// Maps a given name to its common diminutives in both directions: a
    /// formal name yields its nicknames, and a nickname yields its formal
    /// name plus sibling nicknames. Privacy-conservative — over-expansion
    /// only widens what gets scrubbed.
    private static func nicknameVariants(of name: String) -> Set<String> {
        let key = name.lowercased()
        var variants = Set<String>()
        if let direct = nicknames[key] {
            variants.formUnion(direct)
        }
        for (formal, nicks) in nicknames where nicks.contains(key) {
            variants.insert(formal)
            variants.formUnion(nicks)
        }
        variants.remove(key)
        return variants
    }

    // MARK: - NER pass

    /// Replaces any remaining token the personal-name tagger recognises with
    /// `[NAME]`. Runs last so earlier placeholders are already in place; skips
    /// all-caps tokens so it never re-wraps a placeholder like `RECIPIENT`.
    private func redactPersonalNames(in input: String) -> String {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = input
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var ranges: [Range<String.Index>] = []
        tagger.enumerateTags(
            in: input.startIndex ..< input.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard tag == .personalName else { return true }
            let token = input[range]
            // Placeholders are all-caps; real names from typed/ASR text are not.
            if token != token.uppercased() {
                ranges.append(range)
            }
            return true
        }
        guard !ranges.isEmpty else { return input }
        var output = input
        for range in ranges.reversed() {
            output.replaceSubrange(range, with: Self.genericNamePlaceholder)
        }
        return output
    }

    // MARK: - Regex replace

    private func replace(token: String, in input: String, with replacement: String) -> String {
        guard !token.isEmpty else { return input }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    // MARK: - Reference data

    /// Relationship terms that, in a caregiving transcript, overwhelmingly
    /// refer to the care recipient (the parent/grandparent being cared for).
    /// Mapped to `[RECIPIENT]`. Deliberately excludes ambiguous terms like
    /// "aunt"/"uncle" that as often name a caregiver.
    private static let recipientRelationshipTerms: Set<String> = [
        "mom", "mum", "mam", "mama", "momma", "mommy", "mommie", "mother", "ma",
        "dad", "daddy", "papa", "pa", "pop", "pops", "father",
        "grandma", "grandmother", "grandmom", "granny", "nana", "nan", "gran",
        "gammy", "meemaw", "mawmaw", "mimi", "gigi",
        "grandpa", "grandfather", "granddad", "grandad", "grandpop",
        "pawpaw", "pappy", "gramps", "grampa", "poppa", "poppy",
    ]

    /// Common English given-name diminutives, skewed toward the
    /// mid-20th-century names typical of an elder-care recipient. Formal
    /// name (lowercased) → its nicknames.
    private static let nicknames: [String: [String]] = [
        "abigail": ["abby", "gail"],
        "albert": ["al", "bert"],
        "alexander": ["alex", "al", "xander", "sandy"],
        "alexandra": ["alex", "lexi", "sandra", "sandy"],
        "andrew": ["andy", "drew"],
        "anthony": ["tony"],
        "arthur": ["art", "artie"],
        "barbara": ["barb", "babs"],
        "benjamin": ["ben", "benny"],
        "bernard": ["bernie"],
        "catherine": ["cathy", "kate", "katie", "kit"],
        "charles": ["charlie", "chuck", "chas"],
        "christopher": ["chris", "topher"],
        "daniel": ["dan", "danny"],
        "david": ["dave", "davey"],
        "deborah": ["deb", "debbie"],
        "donald": ["don", "donnie"],
        "dorothy": ["dot", "dottie", "dolly"],
        "edward": ["ed", "eddie", "ned", "ted"],
        "eleanor": ["ellie", "nell", "nellie"],
        "elizabeth": ["liz", "lizzie", "beth", "betty", "betsy", "eliza", "libby"],
        "frances": ["fran", "frannie"],
        "francis": ["frank", "frankie"],
        "frederick": ["fred", "freddie"],
        "george": ["georgie"],
        "gerald": ["gerry", "jerry"],
        "gregory": ["greg"],
        "harold": ["harry", "hal"],
        "henry": ["hank", "harry", "hal"],
        "howard": ["howie"],
        "james": ["jim", "jimmy", "jamie"],
        "jennifer": ["jen", "jenny"],
        "jeffrey": ["jeff"],
        "john": ["jack", "johnny"],
        "jonathan": ["jon", "johnny"],
        "joseph": ["joe", "joey"],
        "josephine": ["jo", "josie"],
        "katherine": ["kathy", "kate", "katie", "kit"],
        "kenneth": ["ken", "kenny"],
        "lawrence": ["larry", "laurie"],
        "leonard": ["len", "lenny", "leo"],
        "margaret": ["maggie", "marge", "peg", "peggy", "meg", "greta"],
        "martha": ["marty", "mattie"],
        "matthew": ["matt"],
        "michael": ["mike", "mikey", "mick"],
        "nicholas": ["nick", "nicky"],
        "patricia": ["pat", "patty", "tricia", "trish"],
        "peter": ["pete"],
        "philip": ["phil"],
        "raymond": ["ray"],
        "rebecca": ["becky", "becca"],
        "richard": ["rick", "dick", "rich", "ritchie"],
        "robert": ["rob", "bob", "bobby", "robbie", "bert"],
        "ronald": ["ron", "ronnie"],
        "rosemary": ["rose", "rosie"],
        "samuel": ["sam", "sammy"],
        "stephen": ["steve"],
        "steven": ["steve"],
        "susan": ["sue", "susie", "suzy"],
        "theodore": ["ted", "teddy", "theo"],
        "thomas": ["tom", "tommy"],
        "timothy": ["tim", "timmy"],
        "victoria": ["vicky", "tori"],
        "virginia": ["ginny", "ginger"],
        "walter": ["walt", "wally"],
        "william": ["will", "bill", "billy", "willie", "liam"],
    ]
}
