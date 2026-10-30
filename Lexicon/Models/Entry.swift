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
    }

    let content: Content
    let createdAt: Date
    let id: UUID
    var isBookmarked: Bool

    init(content: Content, createdAt: Date, id: UUID, isBookmarked: Bool) {
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

    var definition: String { content.definition }

    var term: String { content.term }
}

extension Entry {
    static let blueMoon = Entry(
        content: Content(
            uncheckedTerm: "Once in a blue moon",
            definition: "Something that happens very rarely."
        ),
        createdAt: Date(timeIntervalSince1970: 1_790_624_820),
        id: UUID(0),
        isBookmarked: false
    )

    static let burningCandle = Entry(
        content: Content(
            uncheckedTerm: "Burn the candle at both ends",
            definition: "To work early and late until you're exhausted."
        ),
        createdAt: Date(timeIntervalSince1970: 1_778_360_760),
        id: UUID(1),
        isBookmarked: true
    )

    static let wrongTree = Entry(
        content: Content(
            uncheckedTerm: "Barking up the wrong tree",
            definition: "Looking for the answer in the wrong place."
        ),
        createdAt: Date(timeIntervalSince1970: 1_750_701_120),
        id: UUID(2),
        isBookmarked: false
    )

    static let rabbitHole = Entry(
        content: Content(
            uncheckedTerm: "Go down the rabbit hole",
            definition: "To spend much more time on a topic than you planned."
        ),
        createdAt: Date(timeIntervalSince1970: 1_784_009_580),
        id: UUID(3),
        isBookmarked: false
    )

    static let bridgeWater = Entry(
        content: Content(
            uncheckedTerm: "Water under the bridge",
            definition: "Something in the past that is no longer important."
        ),
        createdAt: Date(timeIntervalSince1970: 1_766_151_480),
        id: UUID(4),
        isBookmarked: false
    )

    static let mocks: [Entry] = [.blueMoon, .rabbitHole, .burningCandle, .bridgeWater, .wrongTree]
}
