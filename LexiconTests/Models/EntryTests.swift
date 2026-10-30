//
//  EntryTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import CustomDump
import Dependencies
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct EntryTests {
        @Test
        func theTextIsTrimmed() throws {
            let content = try Entry.Content(
                term: "\n  Break  the ice \t", definition: " \n To start a conversation. \n")
            let entry = try Entry(
                createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                definition: "\r\n Spill \u{3000}",
                id: UUID(0),
                isBookmarked: false,
                term: " Spill the beans "
            )

            expectNoDifference(
                [content.term, content.definition, entry.term, entry.definition],
                ["Break  the ice", "To start a conversation.", "Spill the beans", "Spill"]
            )
        }

        @Test(arguments: ["", " ", "\n\n", "\t \r\n"])
        func aBlankTermIsInvalid(term: String) {
            #expect(throws: Entry.ValidationError.emptyTerm) {
                try Entry.Content(term: term, definition: "Orphan")
            }
        }

        @Test
        func theSizeLimitCountsTheUTF8BytesOfTheTermAndTheDefinition() throws {
            let term = String(repeating: "\u{E9}", count: Entry.Content.maximumSize / 4)
            let definition = String(repeating: "👋", count: (Entry.Content.maximumSize - term.utf8.count) / 4)
            try #require(term.utf8.count + definition.utf8.count == Entry.Content.maximumSize)

            expectNoDifference(
                try Entry.Content(term: term, definition: "\n   " + definition + "   \n"),
                try Entry.Content(term: term, definition: definition)
            )
            #expect(throws: Entry.ValidationError.tooLarge) {
                try Entry.Content(term: term + "a", definition: definition)
            }
            #expect(throws: Entry.ValidationError.tooLarge) {
                try Entry.Content(term: term, definition: definition + "a")
            }
        }

        @Test(arguments: Entry.mocks)
        func everyMockIsAValidEntry(mock: Entry) throws {
            let entry = try Entry(
                createdAt: mock.createdAt,
                definition: mock.definition,
                id: mock.id,
                isBookmarked: mock.isBookmarked,
                term: mock.term
            )

            expectNoDifference(entry, mock)
        }
    }
}
