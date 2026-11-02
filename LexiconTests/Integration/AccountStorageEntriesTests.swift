//
//  AccountStorageEntriesTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 01/11/26.
//

import AccountKit
import ConcurrencyExtras
import CustomDump
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite.IntegrationSuite {
    @Suite
    struct AccountStorageEntriesTests {
        @Test
        func createdEntriesArriveNewestFirstAndDeleteAllRemovesThem() async throws {
            let uid = try await FirebaseEmulators.signIn()
            let snapshots = Recording(await AccountStorage.shared.entries(uid: uid))
            defer { snapshots.cancel() }
            try await snapshots.wait { $0.last?.entries == [] }

            for entry in Entry.mocks {
                try await AccountStorage.shared.create(entry, uid: uid)
            }
            try await snapshots.wait { $0.last?.entries.count == Entry.mocks.count }
            expectNoDifference(
                snapshots.values.last?.entries,
                Entry.mocks.sorted { $0.createdAt > $1.createdAt }
            )

            try await AccountStorage.shared.deleteAllEntries(uid: uid)
            try await snapshots.wait { $0.last?.entries == [] }
        }

        @Test
        func aBookmarkAndAContentUpdateReachTheListener() async throws {
            let uid = try await FirebaseEmulators.signIn()
            try await AccountStorage.shared.create(.blueMoon, uid: uid)
            let snapshots = Recording(await AccountStorage.shared.entries(uid: uid))
            defer { snapshots.cancel() }
            try await snapshots.wait { $0.last?.entries == [.blueMoon] }

            try await AccountStorage.shared.updateBookmark(id: Entry.blueMoon.id, isBookmarked: true, uid: uid)
            try await snapshots.wait { $0.last?.entries.first?.isBookmarked == true }

            let content = try Entry.Content(term: "Hit the books", definition: "To study hard.")
            try await AccountStorage.shared.updateContent(id: Entry.blueMoon.id, content: content, uid: uid)
            try await snapshots.wait { $0.last?.entries.first?.content == content }
        }

        @Test
        func theRulesRefuseAnotherUsersEntries() async throws {
            let owner = try await FirebaseEmulators.signIn()
            try await AccountStorage.shared.create(.blueMoon, uid: owner)
            _ = try await FirebaseEmulators.signIn()

            let error = await #expect(throws: NSError.self) {
                try await AccountStorage.shared.create(.rabbitHole, uid: owner)
            }
            expectNoDifference(error?.code, FirestoreErrorCode.permissionDenied.rawValue)

            let snapshots = Recording(await AccountStorage.shared.entries(uid: owner))
            defer { snapshots.cancel() }
            let failure = try await snapshots.waitForFailure() as NSError
            expectNoDifference(failure.code, FirestoreErrorCode.permissionDenied.rawValue)
            expectNoDifference(snapshots.values, [])
        }
    }
}

private final class Recording<Element: Sendable>: Sendable {
    private let failure = LockIsolated<(any Error)?>(nil)
    private let recorded = LockIsolated<[Element]>([])
    private let task = LockIsolated<Task<Void, Never>?>(nil)

    init(_ stream: AsyncThrowingStream<Element, any Error>) {
        task.setValue(
            Task { [failure, recorded] in
                do {
                    for try await value in stream {
                        recorded.withValue { $0.append(value) }
                    }
                } catch {
                    failure.setValue(error)
                }
            }
        )
    }

    var values: [Element] { recorded.value }

    func cancel() {
        task.value?.cancel()
    }

    func wait(
        timeout: Duration = .seconds(10),
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: ([Element]) -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(recorded.value) {
            guard ContinuousClock.now < deadline else {
                Issue.record(
                    "Timed out. Recorded: \(String(customDumping: recorded.value))", sourceLocation: sourceLocation)
                throw TimeoutError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func waitForFailure(
        timeout: Duration = .seconds(10),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> any Error {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if let failure = failure.value { return failure }
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for a failure.", sourceLocation: sourceLocation)
                throw TimeoutError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct TimeoutError: Error {}

extension BaseSuite {
    @Suite(.enabled(if: FirebaseEmulators.isAvailable), .timeLimit(.minutes(1)))
    struct IntegrationSuite {}
}

enum FirebaseEmulators {
    static let isAvailable = ProcessInfo.processInfo.environment["FIREBASE_EMULATORS"] == "1"

    private static let configuration: Void = {
        let options = FirebaseOptions(googleAppID: "1:123456789000:ios:0000000000000000", gcmSenderID: "123456789000")
        options.apiKey = "AIzaDemoKeyForTheLocalEmulatorsOnly0000"
        options.projectID = "demo-lexicon"
        FirebaseApp.configure(options: options)
        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        useFirestoreEmulator()
    }()

    static func signOut() throws {
        try Auth.auth().signOut()
    }

    static func signIn() async throws -> String {
        configuration
        try? Auth.auth().signOut()
        try await AccountStorage.shared.clearLocalData()
        useFirestoreEmulator()
        return try await Auth.auth().signInAnonymously().user.uid
    }

    private static func useFirestoreEmulator() {
        let settings = Firestore.firestore().settings
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        Firestore.firestore().settings = settings
    }
}
