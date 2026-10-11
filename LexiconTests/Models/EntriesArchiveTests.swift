//
//  EntriesArchiveTests.swift
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
    struct EntriesArchiveTests {
        @Test
        func anExportedFileImportsEveryField() throws {
            let fractionalSecond = Entry(
                createdAt: Date(timeIntervalSince1970: 1_750_000_000.25),
                definition: Entry.blueMoon.definition,
                id: Entry.blueMoon.id,
                isBookmarked: Entry.blueMoon.isBookmarked,
                term: Entry.blueMoon.term
            )
            let entries = [fractionalSecond, .burningCandle]

            let records = try EntriesArchive.records(from: EntriesArchive.data(for: entries))

            expectNoDifference(
                records,
                entries.map {
                    EntriesArchive.Record(
                        createdAt: $0.createdAt,
                        definition: $0.definition,
                        id: $0.id,
                        isBookmarked: $0.isBookmarked,
                        term: $0.term
                    )
                }
            )
        }

        @Test
        func aMissingOrInvalidFieldImportsAsNil() throws {
            let data = Data(
                """
                {
                  "version": 1,
                  "entries": [
                    { "term": "Low-hanging fruit", "id": "not a UUID", "createdAt": 5, "isBookmarked": "yes" },
                    { "createdAt": "2026-10-11T09:30:00Z" }
                  ]
                }
                """
                .utf8
            )

            let records = try EntriesArchive.records(from: data)

            expectNoDifference(
                records,
                [
                    EntriesArchive.Record(term: "Low-hanging fruit"),
                    EntriesArchive.Record(createdAt: Date(timeIntervalSince1970: 1_791_711_000)),
                ]
            )
        }

        @Test(
            arguments: [
                "not JSON",
                "",
                "   ",
                "null",
                #"[{ "term": "Low-hanging fruit" }]"#,
                #"{ "entries": [] }"#,
                #"{ "version": 1 }"#,
                #"{ "version": 1, "entries": [1, 2] }"#,
                #"{ "version": 1, "entries": [{ "term": "Low-hanging fruit" }, null] }"#,
                #"{ "version": 1, "entries": { "term": "Low-hanging fruit" } }"#,
                #"{ "version": 1, "entries": null }"#,
                #"{ "version": "1", "entries": [] }"#,
                #"{ "version": 1.5, "entries": [] }"#,
                #"{ "version": 0, "entries": [] }"#,
                #"{ "version": -1, "entries": [] }"#,
                #"{ "version": null, "entries": [] }"#,
                #"{ "version": true, "entries": [] }"#,
            ]
        )
        func aFileWithADifferentStructureIsInvalid(contents: String) {
            #expect(throws: EntriesArchive.Error.invalid) {
                try EntriesArchive.records(from: Data(contents.utf8))
            }
        }

        @Test(arguments: [2, 99, Int.max])
        func aFileFromANewerVersionIsUnsupported(version: Int) {
            #expect(throws: EntriesArchive.Error.unsupportedVersion) {
                try EntriesArchive.records(from: Data(#"{ "version": \#(version), "entries": "anything" }"#.utf8))
            }
        }

        @Test
        func aWholeNumberVersionWithADecimalPointIsSupported() throws {
            expectNoDifference(try EntriesArchive.records(from: Data(#"{ "version": 1.0, "entries": [] }"#.utf8)), [])
        }

        @Test
        func everyFieldCanBeNull() throws {
            let data = Data(
                #"""
                {
                  "version": 1,
                  "entries": [
                    { "term": null, "definition": null, "id": null, "isBookmarked": null, "createdAt": null }
                  ]
                }
                """#
                .utf8
            )

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record()])
        }

        @Test
        func unknownKeysAreIgnored() throws {
            let data = Data(
                #"""
                {
                  "version": 1,
                  "exportedAt": "2026-10-11T09:30:00Z",
                  "entries": [{ "term": "Low-hanging fruit", "tags": ["a"], "notes": { "a": 1 } }]
                }
                """#
                .utf8
            )

            expectNoDifference(
                try EntriesArchive.records(from: data), [EntriesArchive.Record(term: "Low-hanging fruit")])
        }

        @Test(
            arguments: [
                #""isBookmarked": 0"#,
                #""isBookmarked": 1"#,
                #""isBookmarked": "true""#,
                #""term": 5"#,
                #""term": ["Low-hanging fruit"]"#,
                #""definition": false"#,
                #""id": 5"#,
                #""id": "{6BA7B810-9DAD-11D1-80B4-00C04FD430C8}""#,
                #""id": "6BA7B8109DAD11D180B400C04FD430C8""#,
                #""id": """#,
            ]
        )
        func aFieldOfTheWrongTypeImportsAsNil(field: String) throws {
            let data = Data(#"{ "version": 1, "entries": [{ \#(field) }] }"#.utf8)

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record()])
        }

        @Test
        func aLowercaseIDImportsAsTheSameID() throws {
            let data = Data(
                #"{ "version": 1, "entries": [{ "id": "\#(Entry.blueMoon.id.uuidString.lowercased())" }] }"#.utf8
            )

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record(id: Entry.blueMoon.id)])
        }

        @Test
        func theFirstOfTwoEqualKeysWins() throws {
            let data = Data(#"{ "version": 1, "entries": [{ "term": "First", "term": "Second" }] }"#.utf8)

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record(term: "First")])
        }

        @Test(
            arguments: [
                ("2025-06-15T15:06:40Z", 1_750_000_000.0),
                ("2025-06-15T15:06:40z", 1_750_000_000.0),
                ("2025-06-15T15:06:40.5Z", 1_750_000_000.5),
                ("2025-06-15T15:06:40.25Z", 1_750_000_000.25),
                ("2025-06-15T15:06:40.125Z", 1_750_000_000.125),
                ("2025-06-15T15:06:40.0625Z", 1_750_000_000.0625),
                ("2025-06-15T15:06:40.000000Z", 1_750_000_000.0),
                ("2025-06-15T15:06:40.500000000Z", 1_750_000_000.5),
                ("2025-06-15T17:06:40+02:00", 1_750_000_000.0),
                ("2025-06-15T17:06:40.5+02:00", 1_750_000_000.5),
                ("2025-06-15T09:36:40-05:30", 1_750_000_000.0),
                ("1969-07-20T20:17:40Z", -14_182_940.0),
                ("0001-01-01T00:00:00Z", -62_135_769_600.0),
                ("9999-12-31T23:59:59Z", 253_402_300_799.0),
            ]
        )
        func anISO8601DateImportsAtItsInstant(string: String, timeIntervalSince1970: Double) throws {
            let data = Data(#"{ "version": 1, "entries": [{ "createdAt": "\#(string)" }] }"#.utf8)

            let createdAt = try #require(try EntriesArchive.records(from: data).first?.createdAt)

            #expect(abs(createdAt.timeIntervalSince1970 - timeIntervalSince1970) < 0.000_001)
        }

        @Test(
            arguments: [
                #""2025-06-15""#,
                #""2025-06-15 15:06:40Z""#,
                #""2025-06-15T15:06:40""#,
                #""2025-13-01T00:00:00Z""#,
                #""June 15, 2025""#,
                #""""#,
                "1750000000",
                "true",
            ]
        )
        func aDateInADifferentFormatImportsAsNil(value: String) throws {
            let data = Data(#"{ "version": 1, "entries": [{ "createdAt": \#(value) }] }"#.utf8)

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record()])
        }

        @Test
        func aDateKeepsItsMicrosecondsThroughEveryExport() throws {
            let dates = [
                1_750_000_000.123_456, 1_750_000_000.001, 1_750_000_000.004, 1_750_000_000.999_999_7, -0.000_4,
                -14_182_940.5, 0,
            ]
            let entries = dates.enumerated()
                .map { index, date in
                    Entry(
                        createdAt: Date(timeIntervalSince1970: date),
                        definition: "",
                        id: UUID(index),
                        isBookmarked: false,
                        term: "Term"
                    )
                }

            let data = try EntriesArchive.data(for: entries)
            let records = try EntriesArchive.records(from: data)
            let imported = try zip(entries, records)
                .map { entry, record in
                    let createdAt = try #require(record.createdAt)
                    #expect(abs(createdAt.timeIntervalSince(entry.createdAt)) <= 0.000_001)
                    return Entry(
                        createdAt: createdAt,
                        definition: entry.definition,
                        id: entry.id,
                        isBookmarked: entry.isBookmarked,
                        term: entry.term
                    )
                }

            expectNoDifference(
                String(decoding: try EntriesArchive.data(for: imported), as: UTF8.self),
                String(decoding: data, as: UTF8.self)
            )
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains(#""createdAt" : "2025-06-15T15:06:40.123456Z""#))
            #expect(text.contains(#""createdAt" : "2025-06-15T15:06:40.004000Z""#))
            #expect(text.contains(#""createdAt" : "2025-06-15T15:06:41.000000Z""#))
            #expect(text.contains(#""createdAt" : "1969-12-31T23:59:59.999600Z""#))
        }

        @Test
        func everyCharacterImportsByteForByte() throws {
            let text =
                "🇮🇹 👩🏽‍💻 e\u{301} \u{E9} \u{200B}\u{200D}\u{FEFF} שלום عربي \u{0}\u{7}\u{1B}\u{7F}\u{2028}\u{2029}"
                + " \"quoted\" \\ / \n\r\t {\"version\": 2, \"entries\": []} </script>"
            let entry = Entry(
                createdAt: .init(timeIntervalSince1970: 0),
                definition: text,
                id: UUID(0),
                isBookmarked: false,
                term: text
            )

            let record = try #require(try EntriesArchive.records(from: EntriesArchive.data(for: [entry])).first)

            #expect(record.term.map { Array($0.utf8) } == Array(text.utf8))
            #expect(record.definition.map { Array($0.utf8) } == Array(text.utf8))
        }

        @Test
        func aVeryLongTextImportsWhole() throws {
            let text = String(repeating: "Low-hanging fruit ✓ ", count: 100_000)
            let entry = Entry(
                createdAt: .init(timeIntervalSince1970: 0),
                definition: text,
                id: UUID(0),
                isBookmarked: false,
                term: text
            )

            let record = try #require(try EntriesArchive.records(from: EntriesArchive.data(for: [entry])).first)

            #expect(record.term == text)
            #expect(record.definition == text)
        }

        @Test
        func anExportedFileIsReadable() throws {
            let entry = Entry(
                createdAt: .init(timeIntervalSince1970: 0),
                definition: "Either/or",
                id: UUID(0),
                isBookmarked: false,
                term: "And/or"
            )

            let text = String(decoding: try EntriesArchive.data(for: [entry]), as: UTF8.self)

            #expect(text.contains(#""term" : "And/or""#))
            #expect(text.contains(#""version" : 1"#))
            #expect(text.contains(#""createdAt" : "1970-01-01T00:00:00.000000Z""#))
        }

        @Test
        func anEmptyListExportsAFileThatImports() throws {
            expectNoDifference(try EntriesArchive.records(from: EntriesArchive.data(for: [])), [])
        }

        @Test(arguments: [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian])
        func aFileInADifferentUnicodeEncodingImports(encoding: String.Encoding) throws {
            let data = try #require(#"{ "version": 1, "entries": [{ "term": "Café" }] }"#.data(using: encoding))

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record(term: "Café")])
        }

        @Test
        func aFileWithAByteOrderMarkImports() throws {
            let data = Data([0xEF, 0xBB, 0xBF]) + Data(#"{ "version": 1, "entries": [{ "term": "Café" }] }"#.utf8)

            expectNoDifference(try EntriesArchive.records(from: data), [EntriesArchive.Record(term: "Café")])
        }

        @Test
        func aLargeLibraryExportsAFileThatCanBeImported() throws {
            let definition = String(repeating: "A definition in the user's own words. ", count: 5)
            let entries = (0 ..< 50_000)
                .map { index in
                    Entry(
                        createdAt: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)),
                        definition: definition,
                        id: UUID(index),
                        isBookmarked: index.isMultiple(of: 3),
                        term: "Term number \(index)"
                    )
                }

            let data = try EntriesArchive.data(for: entries)

            #expect(data.count <= Settings.maximumImportFileSize)
            #expect(try EntriesArchive.records(from: data).count == entries.count)
        }

        @Test(arguments: [1, 2, 3, 4, 5])
        func randomEntriesImportExactlyAsTheyExported(seed: UInt64) throws {
            var generator = SplitMix64(seed: seed)
            let entries = (0 ..< 300).map { _ in Entry.random(using: &generator) }

            let records = try EntriesArchive.records(from: EntriesArchive.data(for: entries))

            try #require(records.count == entries.count)
            for (entry, record) in zip(entries, records) {
                #expect(record.id == entry.id)
                #expect(record.term.map { Array($0.utf8) } == Array(entry.term.utf8))
                #expect(record.definition.map { Array($0.utf8) } == Array(entry.definition.utf8))
                #expect(record.isBookmarked == entry.isBookmarked)
                let createdAt = try #require(record.createdAt)
                #expect(abs(createdAt.timeIntervalSince(entry.createdAt)) <= 0.000_001)
            }
        }
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Entry {
    fileprivate static func random(using generator: inout some RandomNumberGenerator) -> Entry {
        Entry(
            createdAt: Date(
                timeIntervalSince1970: Double(
                    Int64.random(in: -2_000_000_000_000 ... 4_000_000_000_000, using: &generator))
                    / 1000
            ),
            definition: String.random(maximumCount: 200, using: &generator),
            id: UUID(uuid: UUID.random(using: &generator)),
            isBookmarked: Bool.random(using: &generator),
            term: String.random(maximumCount: 40, using: &generator)
        )
    }
}

extension String {
    fileprivate static func random(maximumCount: Int, using generator: inout some RandomNumberGenerator) -> String {
        let ranges: [ClosedRange<UInt32>] = [
            0x00 ... 0x7F, 0xA0 ... 0x24F, 0x300 ... 0x36F, 0x590 ... 0x6FF, 0x2000 ... 0x206F, 0x4E00 ... 0x4FFF,
            0xE000 ... 0xE0FF, 0xFE00 ... 0xFEFF, 0x1F300 ... 0x1FAFF,
        ]
        var string = ""
        for _ in 0 ..< Int.random(in: 0 ... maximumCount, using: &generator) {
            let range = ranges.randomElement(using: &generator)!
            if let scalar = Unicode.Scalar(UInt32.random(in: range, using: &generator)) {
                string.unicodeScalars.append(scalar)
            }
        }
        return string
    }
}

extension UUID {
    fileprivate static func random(using generator: inout some RandomNumberGenerator) -> uuid_t {
        var bytes = (0 ..< 16).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
        bytes[6] = bytes[6] & 0x0F | 0x40
        bytes[8] = bytes[8] & 0x3F | 0x80
        return (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }
}
