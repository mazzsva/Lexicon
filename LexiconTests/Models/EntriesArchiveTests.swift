//
//  EntriesArchiveTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import CoreTransferable
import CustomDump
import Dependencies
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct EntriesArchiveTests {
        @Test
        func anExportedFileImportsEveryField() throws {
            let fractionalSecond = try Entry(
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

        @Test(
            arguments: [
                #""id": "not a UUID""#,
                #""id": 5"#,
                #""id": "{6BA7B810-9DAD-11D1-80B4-00C04FD430C8}""#,
                #""id": null"#,
                #""definition": false"#,
                #""definition": null"#,
                #""isBookmarked": "yes""#,
                #""isBookmarked": 1"#,
                #""isBookmarked": null"#,
                #""createdAt": 5"#,
                #""createdAt": null"#,
                #""createdAt": "2025-06-15""#,
                #""createdAt": "2025-06-15T15:06:40""#,
                #""createdAt": 1750000000"#,
            ]
        )
        func aMissingOrInvalidFieldImportsAsNil(field: String) throws {
            let data = Data(#"{ "version": 1, "entries": [{ "term": "Low-hanging fruit", \#(field) }] }"#.utf8)

            expectNoDifference(
                try EntriesArchive.records(from: data),
                [EntriesArchive.Record(term: "Low-hanging fruit")]
            )
        }

        @Test(
            arguments: [
                "not JSON",
                "",
                #"[{ "term": "Low-hanging fruit" }]"#,
                #"{ "entries": [] }"#,
                #"{ "version": 1 }"#,
                #"{ "version": 1, "entries": [1, 2] }"#,
                #"{ "version": "1", "entries": [] }"#,
                #"{ "version": 0, "entries": [] }"#,
            ]
        )
        func aFileWithADifferentStructureIsInvalid(contents: String) {
            #expect(throws: EntriesArchive.ReadError.invalid) {
                try EntriesArchive.records(from: Data(contents.utf8))
            }
        }

        @Test
        func aFileFromANewerVersionIsUnsupported() {
            let version = EntriesArchive.version + 1

            #expect(throws: EntriesArchive.ReadError.unsupportedVersion) {
                try EntriesArchive.records(from: Data(#"{ "version": \#(version), "entries": "anything" }"#.utf8))
            }
        }

        @Test(
            arguments: [
                (
                    Data([0xEF, 0xBB, 0xBF]) + Data(#"{ "version": 1, "entries": [{ "term": "Café" }] }"#.utf8),
                    [EntriesArchive.Record(term: "Café")]
                ),
                (
                    Data(utf16WithByteOrderMark: #"{ "version": 1, "entries": [{ "term": "Café" }] }"#),
                    [EntriesArchive.Record(term: "Café")]
                ),
                (
                    Data(
                        #"""
                        {
                          "version": 1,
                          "exportedAt": "2026-10-11T09:30:00Z",
                          "entries": [{ "term": "Low-hanging fruit", "tags": ["a"], "notes": { "a": 1 } }]
                        }
                        """#
                        .utf8
                    ),
                    [EntriesArchive.Record(term: "Low-hanging fruit")]
                ),
                (
                    Data(#"{ "version": 1, "entries": [{ "id": "00000000-0000-0000-0000-00000000000a" }] }"#.utf8),
                    [EntriesArchive.Record(id: UUID(10))]
                ),
                (Data(#"{ "version": 1, "entries": [] }"#.utf8), []),
            ] as [(Data, [EntriesArchive.Record])]
        )
        func aFileEditedInAnotherAppImports(data: Data, records: [EntriesArchive.Record]) throws {
            expectNoDifference(try EntriesArchive.records(from: data), records)
        }

        @Test(
            arguments: [
                ("2025-06-15T15:06:40Z", 1_750_000_000.0),
                ("2025-06-15T15:06:40.25Z", 1_750_000_000.25),
                ("2025-06-15T17:06:40.5+02:00", 1_750_000_000.5),
            ]
        )
        func anISO8601DateImportsAtItsInstant(string: String, timeIntervalSince1970: Double) throws {
            let data = Data(#"{ "version": 1, "entries": [{ "createdAt": "\#(string)" }] }"#.utf8)

            let createdAt = try #require(try EntriesArchive.records(from: data).first?.createdAt)

            #expect(abs(createdAt.timeIntervalSince1970 - timeIntervalSince1970) < 0.000_001)
        }

        @Test
        func aDateKeepsItsMicrosecondsThroughEveryExport() throws {
            let dates = [
                1_750_000_000.123_456, 1_750_000_000.001, 1_750_000_000.004, 1_750_000_000.999_999_7, -0.000_4,
                -14_182_940.5, 0,
            ]
            let entries = try dates.enumerated()
                .map { index, date in
                    try Entry(
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
                    return try Entry(
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
            expectNoDifference(
                try JSONDecoder().decode(Timestamps.self, from: data).entries.map(\.createdAt),
                [
                    "2025-06-15T15:06:40.123456Z",
                    "2025-06-15T15:06:40.001000Z",
                    "2025-06-15T15:06:40.004000Z",
                    "2025-06-15T15:06:41.000000Z",
                    "1969-12-31T23:59:59.999600Z",
                    "1969-07-20T20:17:39.500000Z",
                    "1970-01-01T00:00:00.000000Z",
                ]
            )
        }

        @Test
        func anExportedFileIsReadable() throws {
            let entry = try Entry(
                createdAt: .init(timeIntervalSince1970: 0),
                definition: "Either/or",
                id: UUID(0),
                isBookmarked: false,
                term: "And/or"
            )

            let text = String(decoding: try EntriesArchive.data(for: [entry]), as: UTF8.self)

            expectNoDifference(
                text,
                """
                {
                  "entries" : [
                    {
                      "createdAt" : "1970-01-01T00:00:00.000000Z",
                      "definition" : "Either/or",
                      "id" : "00000000-0000-0000-0000-000000000000",
                      "isBookmarked" : false,
                      "term" : "And/or"
                    }
                  ],
                  "version" : 1
                }
                """
            )
        }

        @Test
        func aLargeLibraryExportsAFileThatCanBeImported() throws {
            let definition = String(repeating: "A definition in the user's own words. ", count: 5)
            let entries = try (0 ..< 50_000)
                .map { index in
                    try Entry(
                        createdAt: Date(timeIntervalSince1970: 1_750_000_000 + Double(index)),
                        definition: definition,
                        id: UUID(index),
                        isBookmarked: index.isMultiple(of: 3),
                        term: "Term number \(index)"
                    )
                }

            let data = try EntriesArchive.data(for: entries)

            #expect(data.count <= EntriesArchive.maximumFileSize)
        }

        @Test(arguments: [1, 2, 3, 4, 5])
        func randomEntriesImportExactlyAsTheyExported(seed: UInt64) throws {
            var generator = SplitMix64(seed: seed)
            let entries = try (0 ..< 300).map { _ in try Entry.random(using: &generator) }

            let records = try EntriesArchive.records(from: EntriesArchive.data(for: entries))

            expectNoDifference(records.map(Fields.init), entries.map(Fields.init))
            #expect(
                zip(entries, records)
                    .allSatisfy { entry, record in
                        record.createdAt.map { abs($0.timeIntervalSince(entry.createdAt)) <= 0.000_001 } == true
                    }
            )
        }

        @Test
        func theExportedDataIsTheArchiveOfEveryEntry() async throws {
            let data = try await EntriesArchive.Export(entries: Entry.mocks).exported(as: .json)

            expectNoDifference(data, try EntriesArchive.data(for: Entry.mocks))
        }

        @Test
        func theFileNameUsesTheLocalDate() {
            let date = Date(timeIntervalSince1970: 1_791_671_400)

            expectNoDifference(
                EntriesArchive.Export.fileName(date: date, timeZone: TimeZone(identifier: "Europe/Rome")!),
                "Lexicon 2026-10-11.json"
            )
            expectNoDifference(
                EntriesArchive.Export.fileName(date: date, timeZone: TimeZone(identifier: "America/New_York")!),
                "Lexicon 2026-10-10.json"
            )
        }
    }
}

private struct Fields: Equatable {
    let definition: [UInt8]?
    let id: UUID?
    let isBookmarked: Bool?
    let term: [UInt8]?

    init(_ record: EntriesArchive.Record) {
        definition = record.definition.map { Array($0.utf8) }
        id = record.id
        isBookmarked = record.isBookmarked
        term = record.term.map { Array($0.utf8) }
    }

    init(_ entry: Entry) {
        definition = Array(entry.definition.utf8)
        id = entry.id
        isBookmarked = entry.isBookmarked
        term = Array(entry.term.utf8)
    }
}

private struct Timestamps: Decodable {
    struct Item: Decodable {
        let createdAt: String
    }

    let entries: [Item]
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

extension Data {
    fileprivate init(utf16WithByteOrderMark string: String) {
        self.init([0xFF, 0xFE] + string.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] })
    }
}

extension Entry {
    fileprivate static func random(using generator: inout some RandomNumberGenerator) throws -> Entry {
        try Entry(
            createdAt: Date(
                timeIntervalSince1970: Double(
                    Int64.random(in: -2_000_000_000_000 ... 4_000_000_000_000, using: &generator))
                    / 1000
            ),
            definition: String.random(maximumCount: 200, using: &generator),
            id: UUID(uuid: UUID.random(using: &generator)),
            isBookmarked: Bool.random(using: &generator),
            term: "Term " + String.random(maximumCount: 40, using: &generator)
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
            let range = ranges[Int.random(in: ranges.indices, using: &generator)]
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
