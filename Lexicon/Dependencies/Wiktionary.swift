//
//  Wiktionary.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 13/10/26.
//

import Foundation

enum Wiktionary {
    struct FormOf: Equatable, Sendable {
        let isCorrection: Bool
        let title: String
    }

    struct Sense: Equatable, Sendable {
        let formOf: FormOf?
        var labels: [String] = []
        let language: String
        let text: String

        var note: String {
            let labels = Wiktionary.displayedLabels(labels)
            return labels.isEmpty ? text : "(\(labels.joined(separator: ", "))) \(text)"
        }
    }

    private struct Definition: Decodable {
        let definition: String
    }

    private struct LabeledLine {
        let labels: [String]
        let words: Set<Substring>
    }

    private struct Section: Decodable {
        let definitions: [Definition]
        let partOfSpeech: String
    }

    private struct TitleQuery: Decodable {
        struct Page: Decodable {
            let missing: Bool?
            let title: String
        }

        struct Query: Decodable {
            let normalized: [Redirect]?
            let pages: [Page]
            let redirects: [Redirect]?
        }

        struct Redirect: Decodable {
            let from: String
            let to: String
        }

        let query: Query
    }

    private static let abbreviationPrefixes = ["Abbreviation of", "Acronym of", "Initialism of"]

    private static let conversationalLabels: Set = ["colloquial", "informal", "internet slang", "slang", "vulgar"]

    private static let correctionPrefixes = [
        "Common misspelling of", "Eggcorn of", "Misconstruction of", "Misspelling of", "Nonstandard form of",
        "Nonstandard spelling of",
    ]

    private static let ignoredLabels: Set = [
        "anatomy", "archaic", "art", "baseball", "biology", "botany", "cards", "chemistry", "computing", "cricket",
        "dated", "gambling", "geometry", "golf", "grammar", "graph theory", "heraldry", "historical", "law",
        "linguistics", "literal", "literally", "mathematics", "medicine", "military", "music", "nautical", "naval",
        "networking", "obsolete", "philosophy", "phonetics", "phonology", "photography", "physics", "poker",
        "programming", "rare", "rhetoric", "underwater diving", "zoology",
    ]

    private static let ignoredPartsOfSpeech: Set = ["Symbol"]

    private static let maximumPhraseCount = 50

    private static let regionLabels = [
        "Australia": "Australia", "British": "UK", "Canada": "Canada", "Commonwealth": "Commonwealth", "India": "India",
        "Ireland": "Ireland", "Irish": "Ireland", "New Zealand": "New Zealand", "North America": "North America",
        "Scotland": "Scotland", "South Africa": "South Africa", "Southern US": "Southern US", "UK": "UK", "US": "US",
    ]

    private static let registerLabels = [
        "colloquial": "colloquial", "derogatory": "derogatory", "euphemistic": "euphemistic", "formal": "formal",
        "humorous": "humorous", "informal": "informal", "internet slang": "slang", "offensive": "offensive",
        "slang": "slang", "vulgar": "vulgar",
    ]

    private static let stopWords: Set = ["a", "an", "be", "is", "my", "the", "your"]

    static func closestTitles(_ titles: [String], to term: String) -> [String] {
        titles.enumerated()
            .map { offset, title in
                (
                    isInTerm: term.lowercased().contains(title.lowercased()) ? 1 : 0,
                    offset: offset,
                    similarity: similarity(stems(title), stems(term)),
                    title: title
                )
            }
            .filter { $0.similarity >= 0.6 }
            .sorted { ($1.similarity, $1.isInTerm, $0.offset) < ($0.similarity, $0.isInTerm, $1.offset) }
            .map(\.title)
    }

    static func entry(
        title: String,
        senses: [Sense],
        formOfSenses: (_ title: String) async throws -> [Sense]
    ) async throws -> DictionaryEntry? {
        guard let language = language(of: senses) else { return nil }
        if let notes = notes(senses, language: language) {
            return DictionaryEntry(correctForm: nil, senses: notes, title: title)
        }
        guard
            let formOf = senses.first(where: { $0.language == language })?.formOf,
            let notes = notes(try await formOfSenses(formOf.title), language: language)
        else { return nil }
        return DictionaryEntry(correctForm: formOf.isCorrection ? formOf.title : nil, senses: notes, title: title)
    }

    static func existingTitles(_ titles: [String], from data: Data) throws -> [String] {
        let query = try JSONDecoder().decode(TitleQuery.self, from: data).query
        let normalized = Dictionary(
            (query.normalized ?? []).map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        let redirects = Dictionary(
            (query.redirects ?? []).map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        let pages = Set(query.pages.filter { $0.missing != true }.map(\.title))
        var existing: [String] = []
        for title in titles {
            let normalizedTitle = normalized[title] ?? title
            let page = redirects[normalizedTitle] ?? normalizedTitle
            guard pages.contains(page), !existing.contains(page) else { continue }
            existing.append(page)
        }
        return existing
    }

    static func labeled(_ senses: [Sense], wikitext: String) -> [Sense] {
        var linesByLanguage: [String: [LabeledLine]] = [:]
        return senses.map { sense in
            let lines = linesByLanguage[sense.language] ?? labeledLines(inWikitext: wikitext, language: sense.language)
            linesByLanguage[sense.language] = lines
            let words = stems(sense.text)
            var sense = sense
            if let line = lines.max(by: { similarity($0.words, words) < similarity($1.words, words) }),
                similarity(line.words, words) >= 0.5
            {
                sense.labels = line.labels
            }
            return sense
        }
    }

    static func pathComponent(for title: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: allowed)
            ?? title
    }

    static func phrases(in term: String) -> [String] {
        let words = term.lowercased().split(separator: " ")
        guard words.count > 2 else { return [] }
        var phrases: [String] = []
        for count in stride(from: words.count - 1, through: 2, by: -1) {
            for start in (0 ... words.count - count).reversed() {
                let phrase = words[start ..< start + count].joined(separator: " ")
                if stems(phrase).count >= 2, !phrase.contains("|") {
                    phrases.append(phrase)
                }
            }
        }
        return Array(phrases.prefix(maximumPhraseCount))
    }

    static func sense(fromHTML html: String, language: String) -> Sense? {
        guard !html.contains("mw-cite-backlink") else { return nil }
        let text = plainText(fromHTML: html)
        guard
            !text.isEmpty,
            !text.hasPrefix("(Can we verify"),
            !text.hasPrefix("Used other than figuratively or idiomatically")
        else { return nil }
        let formOf = (abbreviationPrefixes.contains(where: text.hasPrefix) ? nil : formOfTitle(inHTML: html))
            .map { title in
                FormOf(isCorrection: correctionPrefixes.contains(where: text.hasPrefix), title: title)
            }
        return Sense(formOf: formOf, language: language, text: text)
    }

    static func senses(from data: Data) throws -> [Sense] {
        let sections = try JSONDecoder().decode([String: [Section]].self, from: data)
        return sections.keys.sorted()
            .flatMap { language in
                sections[language, default: []]
                    .filter { !ignoredPartsOfSpeech.contains($0.partOfSpeech) }
                    .flatMap(\.definitions)
                    .compactMap { sense(fromHTML: $0.definition, language: language) }
            }
    }

    private static func displayedLabels(_ labels: [String]) -> [String] {
        var displayed: [String] = []
        for label in labels {
            guard let shown = regionLabels[label] ?? registerLabels[label.lowercased()], !displayed.contains(shown)
            else { continue }
            displayed.append(shown)
        }
        return displayed
    }

    private static func formOfTitle(inHTML html: String) -> String? {
        guard
            let span = html.range(of: "form-of-definition-link"),
            let end = html.range(of: "</a>", range: span.upperBound ..< html.endIndex),
            let href = html.range(
                of: ##"href="/wiki/[^"#]+"##,
                options: .regularExpression,
                range: span.upperBound ..< end.lowerBound
            )
        else { return nil }
        return html[href].dropFirst(#"href="/wiki/"#.count).removingPercentEncoding?
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func isConversationalLabel(_ label: String) -> Bool {
        conversationalLabels.contains(label.lowercased())
    }

    private static func isIgnoredLabel(_ label: String) -> Bool {
        ignoredLabels.contains(label.lowercased())
    }

    private static func labeledLines(inWikitext wikitext: String, language: String) -> [LabeledLine] {
        guard let name = Locale(identifier: "en").localizedString(forLanguageCode: language) else { return [] }
        var lines: [LabeledLine] = []
        var isInSection = false
        for line in wikitext.split(separator: "\n").map(String.init) {
            if line.hasPrefix("==") && !line.hasPrefix("===") {
                isInSection = line.trimmingCharacters(in: .whitespaces) == "==\(name)=="
            } else if isInSection, line.hasPrefix("#"), line.drop(while: { $0 == "#" }).first?.isWhitespace == true {
                lines.append(
                    LabeledLine(labels: labels(inWikitextLine: line), words: stems(plainText(inWikitextLine: line))))
            }
        }
        return lines
    }

    private static func labels(inWikitextLine line: String) -> [String] {
        line.matches(of: /\{\{(?:lb|lbl|label)\|[a-z-]+\|([^}]*)\}\}/)
            .flatMap { match in
                match.1.split(separator: "|")
                    .map { linkText(in: String($0)).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !["_", "and", "or"].contains($0) && !$0.contains("=") }
            }
    }

    private static func language(of senses: [Sense]) -> String? {
        let languages = Set(senses.map(\.language))
        return languages.contains("en") ? "en" : languages.min()
    }

    private static func linkText(in wikitext: String) -> String {
        wikitext.replacingOccurrences(of: #"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
    }

    private static func notes(_ senses: [Sense], language: String) -> [String]? {
        var definitions: [Sense] = []
        for sense in senses
        where sense.language == language && sense.formOf == nil
            && !definitions.contains(where: { $0.text == sense.text })
        {
            definitions.append(sense)
        }
        let current = definitions.filter { !$0.labels.contains(where: isIgnoredLabel) }
        guard let first = current.first ?? definitions.first else { return nil }
        let conversational = current.first { $0.labels.contains(where: isConversationalLabel) }
        let chosen =
            if let conversational, conversational != first {
                [first, conversational]
            } else {
                Array((current.isEmpty ? [first] : current).prefix(2))
            }
        return chosen.map(\.note)
    }

    private static func plainText(fromHTML html: String) -> String {
        var text =
            html
            .replacingOccurrences(of: #"<(ol|ul)[\s\S]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<style[^>]*>[\s\S]*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return "" }
        text = first.uppercased() + text.dropFirst()
        return [".", "!", "?", "…"].contains(where: text.hasSuffix) ? text : text + "."
    }

    private static func plainText(inWikitextLine line: String) -> String {
        var text = linkText(
            in: line.replacingOccurrences(
                of: #"\{\{(?:lb|lbl|label)\|[^}]*\}\}"#, with: " ", options: .regularExpression)
        )
        for _ in 0 ..< 3 {
            text = text.replacingOccurrences(of: #"\{\{[^{}]*\}\}"#, with: " ", options: .regularExpression)
        }
        return text
    }

    private static func similarity(_ words: Set<Substring>, _ otherWords: Set<Substring>) -> Double {
        guard !words.isEmpty, !otherWords.isEmpty else { return 0 }
        return Double(words.intersection(otherWords).count) / Double(words.union(otherWords).count)
    }

    private static func stems(_ text: String) -> Set<Substring> {
        Set(
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .filter { !stopWords.contains(String($0)) }
                .map { $0.prefix(5) }
        )
    }
}
