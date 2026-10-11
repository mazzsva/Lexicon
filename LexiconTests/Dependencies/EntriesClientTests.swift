//
//  EntriesClientTests.swift
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
    struct EntriesClientTests {
        @Test(
            arguments: [
                (0, [Int]()),
                (1, [1]),
                (500, [500]),
                (501, [500, 1]),
                (1_000, [500, 500]),
                (1_001, [500, 500, 1]),
            ]
        )
        func theWriteBatchesHoldAtMost500Entries(count: Int, batchCounts: [Int]) {
            let entries = (0 ..< count).map { entry(id: $0, size: 0) }

            let batches = Entry.writeBatches(for: entries)

            expectNoDifference(batches.map(\.count), batchCounts)
            expectNoDifference(batches.flatMap { $0 }, entries)
        }

        @Test
        func theWriteBatchesStayUnderTheRequestSize() {
            let entries = (0 ..< 12).map { entry(id: $0, size: 900_000) }

            let batches = Entry.writeBatches(for: entries)

            #expect(batches.allSatisfy { $0.map(\.estimatedDocumentSize).reduce(0, +) <= Entry.maximumBatchSize })
            expectNoDifference(batches.map(\.count), [5, 5, 2])
            expectNoDifference(batches.flatMap { $0 }, entries)
        }

        @Test
        func anOversizeEntryGetsItsOwnWriteBatch() {
            let entries = [entry(id: 0, size: 10), entry(id: 1, size: 2_000_000), entry(id: 2, size: 10)]

            let batches = Entry.writeBatches(for: entries)

            expectNoDifference(batches, [[entries[1]], [entries[0], entries[2]]])
        }

        @Test
        func theSizeEstimateCoversTheFirestoreDocumentSize() {
            let uid = String(repeating: "u", count: 128)
            let entry = entry(id: 0, size: 1_000)
            let nameSize = ["users", uid, "entries", entry.id.uuidString].map { $0.utf8.count + 1 }.reduce(16, +)
            let fieldsSize =
                ("createdAt".utf8.count + 1 + 8)
                + ("definition".utf8.count + 1 + entry.definition.utf8.count + 1)
                + ("isBookmarked".utf8.count + 1 + 1)
                + ("term".utf8.count + 1 + entry.term.utf8.count + 1)
            let firestoreSize = nameSize + fieldsSize + 32

            #expect(entry.estimatedDocumentSize >= firestoreSize)
            #expect(Entry.maximumDocumentSize + entry.estimatedDocumentSize - firestoreSize < 1_048_576)
        }

        @Test
        func anEntryAtTheSizeLimitSharesAWriteBatch() {
            let small = entry(id: 0, size: 10)
            let base = entry(id: 1, size: 0).estimatedDocumentSize
            let atLimit = entry(id: 1, size: Entry.maximumDocumentSize - base)
            #expect(atLimit.estimatedDocumentSize == Entry.maximumDocumentSize)

            expectNoDifference(Entry.writeBatches(for: [small, atLimit]), [[small, atLimit]])
        }

        @Test
        func aWriteBatchFillsUpToTheRequestSize() {
            let base = entry(id: 0, size: 0).estimatedDocumentSize
            let entries = (0 ..< 6).map { entry(id: $0, size: Entry.maximumDocumentSize - base) }
            #expect(entries.allSatisfy { $0.estimatedDocumentSize == Entry.maximumDocumentSize })

            let batches = Entry.writeBatches(for: entries)

            expectNoDifference(batches.map(\.count), [5, 1])
            expectNoDifference(batches.flatMap { $0 }, entries)
        }

        private func entry(id: Int, size: Int) -> Entry {
            Entry(
                createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                definition: String(repeating: "a", count: size),
                id: UUID(id),
                isBookmarked: false,
                term: "Term \(id)"
            )
        }
    }
}
