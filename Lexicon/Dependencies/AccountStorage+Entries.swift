//
//  AccountStorage+Entries.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/10/26.
//

import AccountKit
import FirebaseFirestore

extension AccountStorage {
    func create(_ entry: Entry, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(entry.id.uuidString).setData(entry.documentData)
    }

    func delete(id: Entry.ID, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(id.uuidString).delete()
    }

    func deleteAllEntries(uid: String, didDeleteSomeData: @Sendable () async -> Void = {}) async throws {
        try await deleteAll(in: entriesCollectionName, uid: uid, didDeleteSomeData: didDeleteSomeData)
    }

    func entries(uid: String) async -> AsyncThrowingStream<EntriesSnapshot, any Error> {
        await collectionSnapshots(
            entriesCollectionName,
            uid: uid,
            subject: "Entries",
            includeMetadataChanges: true,
            query: { $0.order(by: "createdAt", descending: true) },
            transform: { snapshot in
                EntriesSnapshot(
                    entries: snapshot.documents.compactMap {
                        Entry(documentID: $0.documentID, data: $0.data())
                    },
                    isSyncing: snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites
                )
            }
        )
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
}

private let entriesCollectionName = "entries"

private func entriesCollection(uid: String) -> CollectionReference {
    AccountStorage.collection(entriesCollectionName, uid: uid)
}
