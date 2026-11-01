//
//  FirestoreRulesTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 01/11/26.
//

import FirebaseFirestore
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite.IntegrationSuite {
    @Suite
    struct FirestoreRulesTests {
        @Test
        func theOwnerCanWriteAValidEntry() async throws {
            let uid = try await FirebaseEmulators.signIn()
            let document = entry(uid, Entry.blueMoon.id)

            try await document.setData(Entry.blueMoon.documentData)
            var data = Entry.blueMoon.documentData
            data["definition"] = ""
            data["isBookmarked"] = true
            try await document.setData(data)
            try await document.delete()
        }

        @Test(
            arguments: [
                ("createdAt", "2026-11-01"),
                ("definition", 1),
                ("isBookmarked", "yes"),
                ("term", ""),
                ("term", "   \n"),
                ("term", 1),
                ("currency", "USD"),
            ] as [(String, any Sendable)])
        func theRulesRefuseAnInvalidEntry(field: String, value: any Sendable) async throws {
            let uid = try await FirebaseEmulators.signIn()
            var data = Entry.blueMoon.documentData
            data[field] = value

            await expectRefused {
                try await entry(uid, Entry.blueMoon.id).setData(data)
            }
        }

        @Test(
            arguments: [
                ("definition", 1),
                ("isBookmarked", "yes"),
                ("term", ""),
                ("currency", "USD"),
            ] as [(String, any Sendable)])
        func theRulesRefuseAnInvalidEntryUpdate(field: String, value: any Sendable) async throws {
            let uid = try await FirebaseEmulators.signIn()
            let document = entry(uid, Entry.blueMoon.id)
            try await document.setData(Entry.blueMoon.documentData)
            var data = Entry.blueMoon.documentData
            data[field] = value

            await expectRefused {
                try await document.setData(data)
            }
            await expectRefused {
                try await document.updateData([field: value])
            }
        }

        @Test(arguments: ["createdAt", "definition", "isBookmarked", "term"])
        func theRulesRefuseAnEntryWithoutAField(field: String) async throws {
            let uid = try await FirebaseEmulators.signIn()
            var data = Entry.blueMoon.documentData
            data[field] = nil

            await expectRefused {
                try await entry(uid, Entry.blueMoon.id).setData(data)
            }
        }

        @Test
        func theRulesAcceptTheLongestEntryTheAppAccepts() async throws {
            let uid = try await FirebaseEmulators.signIn()
            var data = Entry.blueMoon.documentData
            data["term"] = String(repeating: "👋", count: Entry.Content.maximumTermLength / 2)
            data["definition"] = String(repeating: "é", count: Entry.Content.maximumDefinitionLength)

            try await entry(uid, Entry.blueMoon.id).setData(data)
        }

        @Test(
            arguments: [
                ("term", Entry.Content.maximumTermLength + 1),
                ("definition", Entry.Content.maximumDefinitionLength + 1),
            ])
        func theRulesRefuseAnEntryLongerThanTheAppAccepts(field: String, length: Int) async throws {
            let uid = try await FirebaseEmulators.signIn()
            var data = Entry.blueMoon.documentData
            data[field] = String(repeating: "a", count: length)

            await expectRefused {
                try await entry(uid, Entry.blueMoon.id).setData(data)
            }
        }

        @Test
        func theRulesKeepTheCreationDate() async throws {
            let uid = try await FirebaseEmulators.signIn()
            let document = entry(uid, Entry.blueMoon.id)
            try await document.setData(Entry.blueMoon.documentData)
            var data = Entry.blueMoon.documentData
            data["createdAt"] = Timestamp(date: Date(timeIntervalSince1970: 0))

            await expectRefused {
                try await document.setData(data)
            }
        }

        @Test
        func theRulesRefuseAnotherUsersData() async throws {
            let owner = try await FirebaseEmulators.signIn()
            try await entry(owner, Entry.blueMoon.id).setData(Entry.blueMoon.documentData)
            _ = try await FirebaseEmulators.signIn()

            await expectRefused {
                _ = try await entry(owner, Entry.blueMoon.id).getDocument(source: .server)
            }
            await expectRefused {
                try await entry(owner, Entry.blueMoon.id).delete()
            }
            await expectRefused {
                try await entry(owner, Entry.blueMoon.id).setData(Entry.blueMoon.documentData)
            }
            await expectRefused {
                try await entry(owner, Entry.rabbitHole.id).setData(Entry.rabbitHole.documentData)
            }
            await expectRefused {
                _ = try await user(owner).collection("entries").getDocuments(source: .server)
            }
        }

        @Test
        func theRulesRefuseASignedOutUser() async throws {
            let owner = try await FirebaseEmulators.signIn()
            try await entry(owner, Entry.blueMoon.id).setData(Entry.blueMoon.documentData)
            try FirebaseEmulators.signOut()

            await expectRefused {
                _ = try await user(owner).collection("entries").getDocuments(source: .server)
            }
            await expectRefused {
                try await entry(owner, Entry.rabbitHole.id).setData(Entry.rabbitHole.documentData)
            }
        }

        private func expectRefused(
            sourceLocation: SourceLocation = #_sourceLocation,
            _ operation: () async throws -> Void
        ) async {
            do {
                try await operation()
                Issue.record("The rules accepted the operation.", sourceLocation: sourceLocation)
            } catch {
                let error = error as NSError
                #expect(
                    error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue,
                    "Expected a permission error, got \(error).",
                    sourceLocation: sourceLocation
                )
            }
        }

        private func entry(_ uid: String, _ id: Entry.ID) -> DocumentReference {
            user(uid).collection("entries").document(id.uuidString)
        }

        private func user(_ uid: String) -> DocumentReference {
            Firestore.firestore().collection("users").document(uid)
        }
    }
}
