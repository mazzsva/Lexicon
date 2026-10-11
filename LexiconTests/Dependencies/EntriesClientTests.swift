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
                (Entry.maximumBatchCount, [Entry.maximumBatchCount]),
                (Entry.maximumBatchCount + 1, [Entry.maximumBatchCount, 1]),
                (Entry.maximumBatchCount * 2, [Entry.maximumBatchCount, Entry.maximumBatchCount]),
                (Entry.maximumBatchCount * 2 + 1, [Entry.maximumBatchCount, Entry.maximumBatchCount, 1]),
            ]
        )
        func theWriteBatchesHoldAtMostTheMaximumCount(count: Int, batchCounts: [Int]) throws {
            let entries = try (0 ..< count).map { try entry(id: $0, size: 10) }

            let batches = Entry.writeBatches(for: entries)

            expectNoDifference(batches.map(\.count), batchCounts)
            expectNoDifference(batches.flatMap { $0 }, entries)
        }

        @Test
        func aWriteBatchFillsUpToTheRequestSize() throws {
            let entries = try (0 ..< 11).map { try entry(id: $0, size: Entry.maximumBatchSize / 5) }

            let batches = Entry.writeBatches(for: entries)

            expectNoDifference(batches.map(\.count), [5, 5, 1])
            expectNoDifference(batches.flatMap { $0 }, entries)
        }

        @Test
        func theLargestEntryFitsInAWriteBatchAndAFirestoreDocument() {
            let uid = String(repeating: "u", count: 128)
            let nameSize = ["users", uid, "entries", UUID(0).uuidString].map { $0.utf8.count + 1 }.reduce(16, +)
            let fieldsSize =
                ("createdAt".utf8.count + 1 + 8)
                + ("definition".utf8.count + 1 + 1)
                + ("isBookmarked".utf8.count + 1 + 1)
                + ("term".utf8.count + 1 + 1)
            let firestoreSize = nameSize + fieldsSize + Entry.Content.maximumSize + 32

            #expect(Entry.maximumBatchSize >= Entry.Content.maximumSize)
            #expect(firestoreSize < 1_048_576)
        }

        private func entry(id: Int, size: Int) throws -> Entry {
            let term = "Term \(id)"
            let entry = try Entry(
                createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                definition: String(repeating: "a", count: size - term.utf8.count),
                id: UUID(id),
                isBookmarked: false,
                term: term
            )
            try #require(entry.content.size == size)
            return entry
        }
    }
}
