//
//  EntriesImportTests.swift
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
    struct EntriesImportTests {
        private static let now = Date(timeIntervalSince1970: 1_791_711_000)

        @Test(arguments: [0, 1, 3], [0, 1, 3])
        func theCountsCoverEveryRecord(duplicateCount: Int, invalidCount: Int) throws {
            for newCount in [0, 1, 3] {
                let records =
                    Entry.mocks.prefix(duplicateCount).map(Self.record)
                    + (0 ..< invalidCount).map { _ in EntriesArchive.Record(term: "") }
                    + (0 ..< newCount).map { EntriesArchive.Record(id: UUID(100 + $0), term: "New \($0)") }
                let expected = try (0 ..< newCount)
                    .map { index in
                        try Entry(
                            createdAt: Self.now,
                            definition: "",
                            id: UUID(index),
                            isBookmarked: false,
                            term: "New \(index)"
                        )
                    }

                expectNoDifference(
                    Self.imported(records, existing: Entry.mocks),
                    EntriesArchive.Import(
                        duplicateCount: duplicateCount,
                        entries: expected,
                        invalidCount: invalidCount
                    )
                )
            }
        }

        @Test
        func everyImportedEntryGetsANewID() throws {
            let records = [
                EntriesArchive.Record(id: UUID(100), term: "Break the ice"),
                Self.record(.blueMoon),
                EntriesArchive.Record(id: UUID(101), term: " "),
                EntriesArchive.Record(createdAt: Date(timeIntervalSince1970: -62_135_596_801), term: "Too early"),
                EntriesArchive.Record(term: "Spill the beans"),
            ]
            let expected = [
                try Entry(createdAt: Self.now, definition: "", id: UUID(0), isBookmarked: false, term: "Break the ice"),
                try Entry(
                    createdAt: Self.now, definition: "", id: UUID(2), isBookmarked: false, term: "Spill the beans"),
            ]

            expectNoDifference(
                Self.imported(records, existing: Entry.mocks),
                EntriesArchive.Import(duplicateCount: 1, entries: expected, invalidCount: 2)
            )
        }

        @Test
        func anImportNeverOverwritesAnEntryInLexicon() throws {
            let edited = try Entry(
                createdAt: Entry.blueMoon.createdAt,
                definition: "Edited after the export.",
                id: Entry.blueMoon.id,
                isBookmarked: false,
                term: Entry.blueMoon.term
            )
            var largeCopy = Self.record(.burningCandle)
            largeCopy.definition = String(repeating: "a", count: Entry.Content.maximumSize + 1)
            let records = try EntriesArchive.records(from: EntriesArchive.data(for: Entry.mocks)) + [largeCopy]
            let restored = try Entry(
                createdAt: Entry.wrongTree.createdAt,
                definition: Entry.wrongTree.definition,
                id: UUID(0),
                isBookmarked: Entry.wrongTree.isBookmarked,
                term: Entry.wrongTree.term
            )

            expectNoDifference(
                Self.imported(records, existing: [edited, .rabbitHole, .burningCandle, .bridgeWater]),
                EntriesArchive.Import(duplicateCount: 5, entries: [restored], invalidCount: 0)
            )
        }

        @Test
        func anEntryWithTheTextOfAnEntryInLexiconIsADuplicate() throws {
            let records = [
                EntriesArchive.Record(
                    definition: "\n Something that happens very rarely. \t",
                    id: UUID(100),
                    term: "  Once in a blue moon "
                ),
                EntriesArchive.Record(
                    definition: " \n Something that happens very rarely. \t ",
                    id: UUID(101),
                    term: "ONCE IN A BLUE MOON"
                ),
                EntriesArchive.Record(definition: "Something rare.", id: UUID(102), term: "Once in a blue moon"),
            ]
            let expected = [
                try Entry(
                    createdAt: Self.now,
                    definition: "Something that happens very rarely.",
                    id: UUID(0),
                    isBookmarked: false,
                    term: "ONCE IN A BLUE MOON"
                ),
                try Entry(
                    createdAt: Self.now,
                    definition: "Something rare.",
                    id: UUID(1),
                    isBookmarked: false,
                    term: "Once in a blue moon"
                ),
            ]

            expectNoDifference(
                Self.imported(records, existing: Entry.mocks),
                EntriesArchive.Import(duplicateCount: 1, entries: expected, invalidCount: 0)
            )
        }

        @Test
        func theFirstOfTwoRecordsWithTheSameTextWins() throws {
            let records = [
                EntriesArchive.Record(definition: "First", id: UUID(100), isBookmarked: true, term: "Break the ice"),
                EntriesArchive.Record(definition: "First ", id: UUID(101), isBookmarked: false, term: " Break the ice"),
            ]
            let expected = try Entry(
                createdAt: Self.now,
                definition: "First",
                id: UUID(0),
                isBookmarked: true,
                term: "Break the ice"
            )

            expectNoDifference(
                Self.imported(records, existing: []),
                EntriesArchive.Import(duplicateCount: 1, entries: [expected], invalidCount: 0)
            )
        }

        @Test
        func aMissingFieldTakesItsDefault() throws {
            let expected = try Entry(
                createdAt: Self.now,
                definition: "",
                id: UUID(0),
                isBookmarked: false,
                term: "Break the ice"
            )

            expectNoDifference(
                Self.imported([EntriesArchive.Record(term: "Break the ice")], existing: []),
                EntriesArchive.Import(duplicateCount: 0, entries: [expected], invalidCount: 0)
            )
        }

        @Test
        func aDateOutsideTheFirestoreRangeIsInvalid() throws {
            let data = Data(
                #"{ "version": 1, "entries": [{ "term": "Ancient", "createdAt": "0001-01-01T00:00:00Z" }] }"#.utf8
            )
            let records =
                try EntriesArchive.records(from: data)
                + [
                    EntriesArchive.Record(createdAt: Date(timeIntervalSince1970: 253_402_300_800), term: "Too late"),
                    EntriesArchive.Record(term: "Ancient"),
                ]
            let expected = try Entry(
                createdAt: Self.now,
                definition: "",
                id: UUID(2),
                isBookmarked: false,
                term: "Ancient"
            )

            expectNoDifference(
                Self.imported(records, existing: []),
                EntriesArchive.Import(duplicateCount: 0, entries: [expected], invalidCount: 2)
            )
        }

        @Test
        func aReimportAfterAPartialImportSkipsWhatWasWritten() throws {
            let records = ["One", "Two", "Three"].map { EntriesArchive.Record(term: $0) }
            let uuid = UUIDGenerator.incrementing
            let written = Array(Self.imported(records, existing: [], uuid: uuid).entries.prefix(1))
            let expected = [
                try Entry(createdAt: Self.now, definition: "", id: UUID(3), isBookmarked: false, term: "Two"),
                try Entry(createdAt: Self.now, definition: "", id: UUID(4), isBookmarked: false, term: "Three"),
            ]

            expectNoDifference(
                Self.imported(records, existing: written, uuid: uuid),
                EntriesArchive.Import(duplicateCount: 1, entries: expected, invalidCount: 0)
            )
        }

        private static func imported(
            _ records: [EntriesArchive.Record],
            existing: [Entry],
            uuid: UUIDGenerator = .incrementing
        ) -> EntriesArchive.Import {
            EntriesArchive.Import(records: records, existing: existing, now: now, uuid: { uuid() })
        }

        private static func record(_ entry: Entry) -> EntriesArchive.Record {
            EntriesArchive.Record(
                createdAt: entry.createdAt,
                definition: entry.definition,
                id: entry.id,
                isBookmarked: entry.isBookmarked,
                term: entry.term
            )
        }
    }
}
