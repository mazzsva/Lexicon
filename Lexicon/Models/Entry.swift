//
//  Entry.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 13/07/26.
//

import Dependencies
import Foundation

struct Entry: Equatable, Identifiable, Sendable {
    enum ValidationError: Error, Equatable {
        case createdAtOutOfRange
        case emptyTerm
        case tooLarge
    }

    struct Content: Hashable, Sendable {
        static let maximumSize = 1_000_000

        let definition: String
        let term: String

        init(term: String, definition: String) throws(ValidationError) {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { throw .emptyTerm }
            guard term.utf8.count + definition.utf8.count <= Self.maximumSize else { throw .tooLarge }
            self.definition = definition
            self.term = term
        }

        init(storedTerm term: String, definition: String) throws(ValidationError) {
            guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyTerm }
            self.definition = definition
            self.term = term
        }

        fileprivate init(uncheckedTerm term: String, definition: String) {
            self.definition = definition
            self.term = term
        }

        var size: Int { term.utf8.count + definition.utf8.count }
    }

    static let createdAtRange =
        Date(timeIntervalSince1970: -62_135_596_800) ..< Date(timeIntervalSince1970: 253_402_300_800)

    let content: Content
    let createdAt: Date
    let id: UUID
    var isBookmarked: Bool

    init(content: Content, createdAt: Date, id: UUID, isBookmarked: Bool) throws(ValidationError) {
        guard Self.createdAtRange.contains(createdAt) else { throw .createdAtOutOfRange }
        self.content = content
        self.createdAt = createdAt
        self.id = id
        self.isBookmarked = isBookmarked
    }

    init(createdAt: Date, definition: String, id: UUID, isBookmarked: Bool, term: String) throws(ValidationError) {
        try self.init(
            content: Content(term: term, definition: definition),
            createdAt: createdAt,
            id: id,
            isBookmarked: isBookmarked
        )
    }

    private init(uncheckedCreatedAt createdAt: Date, definition: String, id: UUID, isBookmarked: Bool, term: String) {
        content = Content(uncheckedTerm: term, definition: definition)
        self.createdAt = createdAt
        self.id = id
        self.isBookmarked = isBookmarked
    }

    var definition: String { content.definition }

    var term: String { content.term }
}

extension Entry {
    static let blueMoon = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_750_000_000),
        definition: "Something that happens very rarely.",
        id: UUID(0),
        isBookmarked: true,
        term: "Once in a blue moon"
    )

    static let burningCandle = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_749_000_000),
        definition: "To work early and late until you're exhausted.",
        id: UUID(1),
        isBookmarked: false,
        term: "Burn the candle at both ends"
    )

    static let lowHangingFruit = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_748_000_000),
        definition: "The easiest wins, taken first.",
        id: UUID(2),
        isBookmarked: false,
        term: "Low-hanging fruit"
    )

    static let mocks: [Entry] = [.blueMoon, .burningCandle, .lowHangingFruit]
}
