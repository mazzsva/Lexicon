//
//  EntriesClientTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import Dependencies
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct EntriesClientTests {
        @Test
        func theLargestEntryFitsInAFirestoreDocument() {
            let uid = String(repeating: "u", count: 128)
            let nameSize = ["users", uid, "entries", UUID(0).uuidString].map { $0.utf8.count + 1 }.reduce(16, +)
            let fieldsSize =
                ("createdAt".utf8.count + 1 + 8)
                + ("definition".utf8.count + 1 + 1)
                + ("isBookmarked".utf8.count + 1 + 1)
                + ("term".utf8.count + 1 + 1)
            let firestoreSize = nameSize + fieldsSize + Entry.Content.maximumSize + 32

            #expect(firestoreSize < 1_048_576)
        }
    }
}
