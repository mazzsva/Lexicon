//
//  EntriesClient.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import AccountKit
import Dependencies
import DependenciesMacros
import FirebaseFirestore
import Foundation
import IssueReporting
import os

@DependencyClient
struct EntriesClient: Sendable {
    var clearLocalData: @Sendable () async throws -> Void
    var create: @Sendable (_ entry: Entry, _ uid: String) async throws -> Void
    var delete: @Sendable (_ id: Entry.ID, _ uid: String) async throws -> Void
    var deleteAll: @Sendable (_ uid: String) async throws -> Void

    var entries: @Sendable (_ uid: String) async -> AsyncThrowingStream<EntriesSnapshot, any Error> = { _ in
        AsyncThrowingStream { _ in }
    }

    var updateBookmark: @Sendable (_ id: Entry.ID, _ isBookmarked: Bool, _ uid: String) async throws -> Void
    var updateContent: @Sendable (_ id: Entry.ID, _ content: Entry.Content, _ uid: String) async throws -> Void
}

struct EntriesSnapshot: Equatable, Sendable {
    let entries: [Entry]
    let isSyncing: Bool
}

extension EntriesSnapshot {
    static let empty = EntriesSnapshot(entries: [], isSyncing: false)
    static let mock = EntriesSnapshot(entries: Entry.mocks, isSyncing: false)
    static let syncing = EntriesSnapshot(entries: Entry.mocks, isSyncing: true)
}

extension EntriesClient: DependencyKey {
    static var liveValue: EntriesClient {
        EntriesClient(
            clearLocalData: {
                try await AccountStorage.shared.clearLocalData()
            },
            create: { entry, uid in
                try await AccountStorage.shared.create(entry, uid: uid)
            },
            delete: { id, uid in
                try await AccountStorage.shared.delete(id: id, uid: uid)
            },
            deleteAll: { uid in
                try await AccountStorage.shared.deleteAllEntries(uid: uid)
            },
            entries: { uid in
                await AccountStorage.shared.entries(uid: uid)
            },
            updateBookmark: { id, isBookmarked, uid in
                try await AccountStorage.shared.updateBookmark(id: id, isBookmarked: isBookmarked, uid: uid)
            },
            updateContent: { id, content, uid in
                try await AccountStorage.shared.updateContent(id: id, content: content, uid: uid)
            }
        )
    }

    static var previewValue: EntriesClient {
        EntriesClient(
            clearLocalData: {},
            create: { _, _ in },
            delete: { _, _ in },
            deleteAll: { _ in },
            entries: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.mock)
                }
            },
            updateBookmark: { _, _, _ in },
            updateContent: { _, _, _ in }
        )
    }

    static var testValue: EntriesClient {
        EntriesClient()
    }
}

extension DependencyValues {
    var entriesClient: EntriesClient {
        get { self[EntriesClient.self] }
        set { self[EntriesClient.self] = newValue }
    }
}

extension Entry {
    init?(documentID: String, data: [String: Any]) {
        guard
            let createdAt = data["createdAt"] as? Timestamp,
            let definition = data["definition"] as? String,
            let id = UUID(uuidString: documentID),
            id.uuidString == documentID,
            let isBookmarked = data["isBookmarked"] as? Bool,
            let term = data["term"] as? String,
            let content = try? Entry.Content(storedTerm: term, definition: definition)
        else {
            logger.error("Skipping entry document \(documentID, privacy: .public) that failed to decode.")
            reportIssue("Skipping entry document \(documentID) that failed to decode.")
            return nil
        }
        self.init(content: content, createdAt: createdAt.dateValue(), id: id, isBookmarked: isBookmarked)
    }

    var documentData: [String: Any] {
        [
            "createdAt": Timestamp(date: createdAt),
            "definition": definition,
            "isBookmarked": isBookmarked,
            "term": term,
        ]
    }
}

private let logger = Logger(category: "EntriesClient")
