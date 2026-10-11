//
//  EntriesExportTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import ComposableArchitecture
import CoreTransferable
import CustomDump
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct EntriesExportTests {
        @Test
        func theExportedDataIsTheArchiveOfEveryEntry() async throws {
            let data = try await EntriesArchive.Export(entries: Entry.mocks).exported(as: .json)

            expectNoDifference(data, try EntriesArchive.data(for: Entry.mocks))
            expectNoDifference(
                try EntriesArchive.records(from: data).map(\.id),
                Entry.mocks.map(\.id)
            )
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

        @Test
        func theFileNameStaysASCIIInEveryLocale() {
            let fileName = EntriesArchive.Export.fileName(
                date: Date(timeIntervalSince1970: 1_791_711_000),
                timeZone: TimeZone(identifier: "Asia/Bangkok")!
            )

            #expect(fileName.allSatisfy { $0.isASCII })
            #expect(!fileName.contains { "/:\\\\?%*|\"<>".contains($0) })
            #expect(UTType(filenameExtension: (fileName as NSString).pathExtension)?.conforms(to: .json) == true)
        }

        @Test
        func theSettingsExportEveryEntryWhateverTheFilters() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
            state.isShowingBookmarkedOnly = true
            state.searchText = "moon"

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.settingsButtonTapped) {
                $0.destination = .settings(
                    Settings.State(
                        entries: SharedReader(value: IdentifiedArray(uniqueElements: Entry.mocks)),
                        user: .mock
                    )
                )
            }
            expectNoDifference(store.state.destination?.settings?.entries?.elements, Entry.mocks)
            #expect(store.state.destination?.settings?.canExportEntries == true)
        }

        @Test
        func theSettingsFollowTheEntriesWhileTheyAreOpen() async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = [] }

            let store = TestStore(initialState: state) {
                Home()
            }
            store.exhaustivity = .off

            await store.send(.settingsButtonTapped)
            #expect(store.state.destination?.settings?.canExportEntries == false)

            await store.send(.entriesUpdated(.mock))
            expectNoDifference(store.state.destination?.settings?.entries?.elements, Entry.mocks)
            #expect(store.state.destination?.settings?.canExportEntries == true)
        }

        @Test
        func reimportingAnExportIntoTheSameAccountHasNothingToImport() async {
            let store = TestStore(
                initialState: Settings.State(
                    entries: SharedReader(value: IdentifiedArray(uniqueElements: Entry.mocks)),
                    isEntriesSynced: true,
                    user: .mock
                )
            ) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in try await EntriesArchive.Export(entries: Entry.mocks).exported(as: .json)
                }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .importHasOnlyDuplicates
            }
        }

        @Test
        func anExportRestoresEveryFieldIntoAnEmptyAccount() async {
            let entries =
                [
                    Entry(
                        createdAt: Date(timeIntervalSince1970: 1_750_000_000.5),
                        definition: "First line.\n\n  Indented second line.",
                        id: UUID(7),
                        isBookmarked: true,
                        term: "Héllo wörld 👋 \"quoted\" \\ back/slash"
                    ),
                    Entry(
                        createdAt: Date(timeIntervalSince1970: 1_740_000_000),
                        definition: "",
                        id: UUID(8),
                        isBookmarked: false,
                        term: "日本語"
                    ),
                ] + Entry.mocks

            var homeState = Home.State(user: User(email: nil, uid: "other-uid"))
            homeState.$entries.withLock { $0 = [] }
            homeState.isSyncing = false
            homeState.destination = .settings(
                Settings.State(entries: SharedReader(homeState.$entries), isEntriesSynced: true, user: homeState.user)
            )

            let store = TestStore(initialState: homeState) {
                Home()
            } withDependencies: {
                $0.entriesClient.saveAll = { saved, uid in
                    expectNoDifference(saved, entries)
                    expectNoDifference(uid, "other-uid")
                }
                $0.fileClient.read = { _, _ in try await EntriesArchive.Export(entries: entries).exported(as: .json) }
                $0.hapticsClient.success = {}
            }

            await store.send(.destination(.presented(.settings(.importFilePicked(.success(URL(filePath: "/a.json")))))))
            await store.receive(\.destination.presented.settings.importFileLoaded) {
                $0.destination?
                    .modify(\.settings) {
                        $0.alert = .confirmImport(entries, duplicateCount: 0, invalidCount: 0)
                    }
            }
            await store.send(.destination(.presented(.settings(.alert(.presented(.confirmImport(entries))))))) {
                $0.destination?.modify(\.settings) { $0.alert = nil }
            }
            await store.receive(\.destination.presented.settings.delegate.didImport, entries) {
                $0.destination = nil
            }
            await store.finish()
        }

        @Test
        func theCreationDateKeepsMillisecondPrecision() throws {
            let entry = Entry(
                createdAt: Date(timeIntervalSince1970: 1_750_000_000.123456),
                definition: "",
                id: UUID(9),
                isBookmarked: false,
                term: "Precision"
            )

            let records = try EntriesArchive.records(from: EntriesArchive.data(for: [entry]))

            let createdAt = try #require(records.first?.createdAt)
            #expect(abs(createdAt.timeIntervalSince(entry.createdAt)) < 0.001)
        }

        @Test
        func anOldExportKeepsEditsAndBringsBackDeletedEntries() async {
            var edited = Entry.blueMoon
            edited.definition = "Edited after the export."
            edited.isBookmarked = false

            let store = TestStore(
                initialState: Settings.State(
                    entries: SharedReader(value: [edited, .burningCandle]),
                    isEntriesSynced: true,
                    user: .mock
                )
            ) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in try EntriesArchive.data(for: Entry.mocks) }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .confirmImport([.lowHangingFruit], duplicateCount: 2, invalidCount: 0)
            }
        }

        @Test
        func anOldFileIsTrimmedAndTermsThatDifferOnlyInCaseAreKept() async {
            let file = Data(
                """
                {
                  "version": 1,
                  "entries": [
                    {
                      "id": "\(UUID(5))",
                      "term": "ONCE IN A BLUE MOON",
                      "definition": " \\n Something rare. \\t ",
                      "isBookmarked": false,
                      "createdAt": "2025-06-15T15:06:40.000Z"
                    }
                  ]
                }
                """
                .utf8
            )
            let imported = Entry(
                createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                definition: "Something rare.",
                id: UUID(5),
                isBookmarked: false,
                term: "ONCE IN A BLUE MOON"
            )

            let store = TestStore(
                initialState: Settings.State(
                    entries: SharedReader(value: IdentifiedArray(uniqueElements: Entry.mocks)),
                    isEntriesSynced: true,
                    user: .mock
                )
            ) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in file }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .confirmImport([imported], duplicateCount: 0, invalidCount: 0)
            }
        }
    }
}
