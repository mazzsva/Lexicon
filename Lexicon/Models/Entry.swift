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
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_790_624_820),
        definition: "Something that happens very rarely.",
        id: UUID(0),
        isBookmarked: false,
        term: "Once in a blue moon"
    )

    static let burningCandle = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_778_360_760),
        definition: "To work early and late until you're exhausted.",
        id: UUID(1),
        isBookmarked: true,
        term: "Burn the candle at both ends"
    )

    static let wrongTree = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_750_701_120),
        definition: "Looking for the answer in the wrong place.",
        id: UUID(2),
        isBookmarked: false,
        term: "Barking up the wrong tree"
    )

    static let rabbitHole = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_784_009_580),
        definition: "To spend much more time on a topic than you planned.",
        id: UUID(3),
        isBookmarked: false,
        term: "Go down the rabbit hole"
    )

    static let bridgeWater = Entry(
        uncheckedCreatedAt: Date(timeIntervalSince1970: 1_766_151_480),
        definition: "Something in the past that is no longer important.",
        id: UUID(4),
        isBookmarked: false,
        term: "Water under the bridge"
    )

    static let mocks: [Entry] = [.blueMoon, .rabbitHole, .burningCandle, .bridgeWater, .wrongTree]
}
