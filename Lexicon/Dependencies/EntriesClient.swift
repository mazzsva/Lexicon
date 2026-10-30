//
//  EntriesClient.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

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
                try await FirestoreStorage.shared.clearLocalData()
            },
            create: { entry, uid in
                try await FirestoreStorage.shared.create(entry, uid: uid)
            },
            delete: { id, uid in
                try await FirestoreStorage.shared.delete(id: id, uid: uid)
            },
            deleteAll: { uid in
                try await FirestoreStorage.shared.deleteAll(uid: uid)
            },
            entries: { uid in
                await FirestoreStorage.shared.entries(uid: uid)
            },
            updateBookmark: { id, isBookmarked, uid in
                try await FirestoreStorage.shared.updateBookmark(id: id, isBookmarked: isBookmarked, uid: uid)
            },
            updateContent: { id, content, uid in
                try await FirestoreStorage.shared.updateContent(id: id, content: content, uid: uid)
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

private actor FirestoreStorage {
    static let shared = FirestoreStorage()

    private var clearing: Task<Void, any Error>?

    func clearLocalData() async throws {
        if let clearing {
            return try await clearing.value
        }
        let clearing = Task {
            let firestore = Firestore.firestore()
            try await firestore.terminate()
            try await firestore.clearPersistence()
        }
        self.clearing = clearing
        defer { self.clearing = nil }
        try await clearing.value
    }

    func create(_ entry: Entry, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(entry.id.uuidString).setData(entry.documentData)
    }

    func delete(id: Entry.ID, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(id.uuidString).delete()
    }

    func deleteAll(uid: String) async throws {
        await waitForClearing()
        while true {
            try Task.checkCancellation()
            let snapshot = try await entriesCollection(uid: uid).limit(to: 500).getDocuments()
            guard !snapshot.documents.isEmpty else { return }
            let batch = Firestore.firestore().batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }
    }

    func entries(uid: String) async -> AsyncThrowingStream<EntriesSnapshot, any Error> {
        await waitForClearing()
        return AsyncThrowingStream { continuation in
            nonisolated(unsafe) let listener = entriesCollection(uid: uid)
                .order(by: "createdAt", descending: true)
                .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let snapshot else {
                        reportIssue("Entries listener reported neither a snapshot nor an error.")
                        return
                    }
                    continuation.yield(
                        EntriesSnapshot(
                            entries: snapshot.documents.compactMap(Entry.init(document:)),
                            isSyncing: snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites
                        )
                    )
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func updateBookmark(id: Entry.ID, isBookmarked: Bool, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(id.uuidString).updateData(["isBookmarked": isBookmarked])
    }

    func updateContent(id: Entry.ID, content: Entry.Content, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(id.uuidString)
            .updateData(["definition": content.definition, "term": content.term])
    }

    private func waitForClearing() async {
        _ = try? await clearing?.value
    }
}

private func entriesCollection(uid: String) -> CollectionReference {
    Firestore.firestore().collection("users").document(uid).collection("entries")
}

extension Entry {
    fileprivate init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let createdAt = data["createdAt"] as? Timestamp,
            let definition = data["definition"] as? String,
            let id = UUID(uuidString: document.documentID),
            id.uuidString == document.documentID,
            let isBookmarked = data["isBookmarked"] as? Bool,
            let term = data["term"] as? String,
            let content = try? Entry.Content(storedTerm: term, definition: definition),
            let entry = try? Entry(
                content: content, createdAt: createdAt.dateValue(), id: id, isBookmarked: isBookmarked)
        else {
            logger.error("Skipping entry document \(document.documentID, privacy: .public) that failed to decode.")
            reportIssue("Skipping entry document \(document.documentID) that failed to decode.")
            return nil
        }
        self = entry
    }

    fileprivate var documentData: [String: Any] {
        [
            "createdAt": Timestamp(date: createdAt),
            "definition": definition,
            "isBookmarked": isBookmarked,
            "term": term,
        ]
    }
}

private let logger = Logger(category: "EntriesClient")
