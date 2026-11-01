//
//  FirestoreStorage.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/10/26.
//

import FirebaseFirestore
import Foundation
import IssueReporting

actor FirestoreStorage {
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
                            entries: snapshot.documents.compactMap {
                                Entry(documentID: $0.documentID, data: $0.data())
                            },
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
