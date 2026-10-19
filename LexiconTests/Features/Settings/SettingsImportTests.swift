//
//  SettingsImportTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import ComposableArchitecture
import CustomDump
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct SettingsImportTests {
        private static let now = Date(timeIntervalSince1970: 1_791_711_000)
        private static let url = URL(filePath: "/Entries.json")

        @Test
        func theImportButtonOpensTheFileImporter() async {
            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importEntriesButtonTapped) {
                $0.destination = .fileImporter
            }
            await store.send(.fileImporterPresentationChanged(false)) {
                $0.destination = nil
            }
        }

        @Test
        func theImporterClosingAfterAPickKeepsTheLoad() async {
            let clock = TestClock()

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in
                    try await clock.sleep(for: .seconds(1))
                    throw FileClient.ReadError.tooLarge
                }
            }

            await store.send(.importEntriesButtonTapped) {
                $0.destination = .fileImporter
            }
            await store.send(.importFilePicked(.success(Self.url))) {
                $0.destination = .loadingImportFile
            }
            await store.send(.fileImporterPresentationChanged(false))
            await clock.advance(by: .seconds(1))
            await store.receive(\.importFileLoaded) {
                $0.destination = .alert(.importFailed(FileClient.ReadError.tooLarge))
            }
        }

        @Test
        func theImporterClosingUnderAnAlertKeepsTheAlert() async {
            let store = TestStore(initialState: Self.state(entries: [], destination: .fileImporter)) {
                Settings()
            }

            await store.send(.signOutFailed(SignOutFailure())) {
                $0.destination = .alert(.signOutFailed)
            }
            await store.send(.fileImporterPresentationChanged(false))
        }

        @Test(
            arguments: [
                (.loading, false),
                (.failed, false),
                (.loaded(IdentifiedArray(uniqueElements: Entry.mocks)), true),
            ] as [(EntriesPhase, Bool)]
        )
        func theImportButtonDoesNothingUntilTheEntriesAndTheFileLoad(phase: EntriesPhase, isLoadingFile: Bool) async {
            let store = TestStore(
                initialState: Self.state(phase: phase, destination: isLoadingFile ? .loadingImportFile : nil)
            ) {
                Settings()
            }

            await store.send(.importEntriesButtonTapped)
        }

        @Test
        func aPickedFileAsksToImportOnlyTheNewValidEntries() async throws {
            let url = URL(filePath: "/Entries.json")
            let file = Data(
                """
                {
                  "version": 1,
                  "entries": [
                    { "id": "\(Entry.blueMoon.id)", "term": "Edited in another app" },
                    {
                      "id": "\(UUID(5))",
                      "term": "  Break the ice  ",
                      "definition": "  To start a conversation.  ",
                      "isBookmarked": true,
                      "createdAt": "2025-06-15T15:06:40.000Z"
                    },
                    { "term": "   " }
                  ]
                }
                """
                .utf8
            )
            let imported = [
                try Entry(
                    createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                    definition: "To start a conversation.",
                    id: UUID(9),
                    isBookmarked: true,
                    term: "Break the ice"
                )
            ]

            let store = TestStore(initialState: Self.state(entries: Entry.mocks)) {
                Settings()
            } withDependencies: {
                $0.date.now = Self.now
                $0.fileClient.read = { readURL, maximumSize in
                    expectNoDifference(readURL, url)
                    expectNoDifference(maximumSize, EntriesArchive.maximumFileSize)
                    return file
                }
                $0.uuid = .constant(UUID(9))
            }

            await store.send(.importFilePicked(.success(url))) {
                $0.destination = .loadingImportFile
            }
            await store.receive(\.importFileLoaded) {
                $0.destination = .alert(
                    .confirmImport(EntriesArchive.Import(duplicateCount: 1, entries: imported, invalidCount: 1))
                )
            }
            await store.send(.destination(.presented(.alert(.confirmImport(imported))))) {
                $0.destination = nil
            }
            await store.receive(\.delegate.didImport, imported)
        }

        @Test(
            arguments: [
                ([], .importHasNoEntries),
                ([EntriesArchive.Record(term: "   ")], .importHasNoEntries),
                (
                    [
                        EntriesArchive.Record(id: Entry.blueMoon.id, term: "Edited in another app"),
                        EntriesArchive.Record(term: "   "),
                    ],
                    .importHasOnlyDuplicates
                ),
            ] as [([EntriesArchive.Record], AlertState<Settings.Alert>)]
        )
        func aFileWithoutNewEntriesHasNothingToImport(
            records: [EntriesArchive.Record],
            alert: AlertState<Settings.Alert>
        ) async {
            let store = TestStore(initialState: Self.state(entries: Entry.mocks, destination: .loadingImportFile)) {
                Settings()
            } withDependencies: {
                $0.date.now = Self.now
            }

            await store.send(.importFileLoaded(.success(records))) {
                $0.destination = .alert(alert)
            }
        }

        @Test(arguments: [EntriesPhase.loading, .failed])
        func aFileThatLoadsBeforeTheEntriesIsAProgrammerError(phase: EntriesPhase) async {
            let store = TestStore(initialState: Self.state(phase: phase, destination: .loadingImportFile)) {
                Settings()
            }

            await withKnownIssue {
                await store.send(.importFileLoaded(.success([EntriesArchive.Record(term: "Break the ice")]))) {
                    $0.destination = nil
                }
            } matching: {
                $0.comments.contains { $0.rawValue == "The import file loaded while the entries were not loaded." }
            }
        }

        @Test
        func theConfirmationNamesEachKindOfSkippedEntry() {
            expectNoDifference(
                AlertState<Settings.Alert>
                    .confirmImport(EntriesArchive.Import(duplicateCount: 0, entries: Entry.mocks, invalidCount: 0))
                    .title,
                TextState("Import ^[\(3) Entry](inflect: true)?")
            )
            expectNoDifference(
                AlertState<Settings.Alert>
                    .confirmImport(EntriesArchive.Import(duplicateCount: 0, entries: [.blueMoon], invalidCount: 0))
                    .message,
                nil
            )
            expectNoDifference(
                AlertState<Settings.Alert>
                    .confirmImport(EntriesArchive.Import(duplicateCount: 2, entries: [.blueMoon], invalidCount: 0))
                    .message,
                TextState("^[\(2) entry](inflect: true) already in Lexicon will be skipped.")
            )
            expectNoDifference(
                AlertState<Settings.Alert>
                    .confirmImport(EntriesArchive.Import(duplicateCount: 0, entries: [.blueMoon], invalidCount: 1))
                    .message,
                TextState("^[\(1) entry](inflect: true) can't be imported and will be skipped.")
            )
            expectNoDifference(
                AlertState<Settings.Alert>
                    .confirmImport(EntriesArchive.Import(duplicateCount: 3, entries: [.blueMoon], invalidCount: 2))
                    .message,
                TextState(
                    "^[\(3) entry](inflect: true) already in Lexicon and ^[\(2) entry](inflect: true) that can't be imported will be skipped."
                )
            )
        }

        @Test
        func aFileThatFailsToLoadShowsAnAlert() async {
            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in throw FileClient.ReadError.tooLarge }
            }

            await store.send(.importFilePicked(.success(Self.url))) {
                $0.destination = .loadingImportFile
            }
            await store.receive(\.importFileLoaded) {
                $0.destination = .alert(.importFailed(FileClient.ReadError.tooLarge))
            }
        }

        @Test
        func aFailedPickShowsAnAlert() async {
            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFilePicked(.failure(CocoaError(.fileReadNoPermission)))) {
                $0.destination = .alert(.importFailed(CocoaError(.fileReadNoPermission)))
            }
        }

        @Test(
            arguments: [
                (FileClient.ReadError.tooLarge as any Error, "This file is too large to import."),
                (EntriesArchive.ReadError.invalid, "This file isn't a Lexicon export."),
                (EntriesArchive.ReadError.unsupportedVersion, "This file was made by a newer version of Lexicon."),
                (CocoaError(.fileReadNoPermission), "The file couldn't be opened."),
            ]
        )
        func eachImportFailureHasItsOwnMessage(error: any Error, message: String) {
            expectNoDifference(AlertState<Settings.Alert>.importFailed(error).message, TextState(message))
        }

        @Test
        func aSecondPickReplacesTheFirstLoad() async throws {
            let clock = TestClock()
            let first = URL(filePath: "/First.json")
            let second = URL(filePath: "/Second.json")
            let secondEntry = try Entry(
                createdAt: Self.now,
                definition: "",
                id: UUID(5),
                isBookmarked: false,
                term: "Second"
            )
            let imported = try Entry(
                createdAt: Self.now,
                definition: "",
                id: UUID(9),
                isBookmarked: false,
                term: "Second"
            )

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.date.now = Self.now
                $0.fileClient.read = { url, _ in
                    if url == first {
                        try await clock.sleep(for: .seconds(2))
                        return try EntriesArchive.data(for: [.blueMoon])
                    }
                    try await clock.sleep(for: .seconds(1))
                    return try EntriesArchive.data(for: [secondEntry])
                }
                $0.uuid = .constant(UUID(9))
            }

            await store.send(.importFilePicked(.success(first))) {
                $0.destination = .loadingImportFile
            }
            await store.send(.importFilePicked(.success(second)))
            await clock.advance(by: .seconds(1))
            await store.receive(\.importFileLoaded) {
                $0.destination = .alert(
                    .confirmImport(EntriesArchive.Import(duplicateCount: 0, entries: [imported], invalidCount: 0))
                )
            }
            await clock.advance(by: .seconds(1))
        }

        @Test(arguments: ConfirmationButton.allCases)
        func aLoadThatEndsUnderAConfirmationIsDropped(button: ConfirmationButton) async {
            let clock = TestClock()
            let isReadCanceled = LockIsolated(false)

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in
                    try await withTaskCancellationHandler {
                        try await clock.sleep(for: .seconds(1))
                        return try EntriesArchive.data(for: [.blueMoon])
                    } onCancel: {
                        isReadCanceled.setValue(true)
                    }
                }
            }

            await store.send(.importFilePicked(.success(Self.url))) {
                $0.destination = .loadingImportFile
            }
            await store.send(button.action) {
                $0.destination = .alert(button.alert)
            }
            await clock.advance(by: .seconds(1))
            #expect(isReadCanceled.value)
        }

        @Test
        func closingTheSettingsDuringTheLoadDropsTheResult() async {
            let clock = TestClock()
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded([]) }
            state.destination = .settings(
                Settings.State(entries: SharedReader(state.$entries), user: .mock)
            )

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.fileClient.read = { _, _ in
                    try await clock.sleep(for: .seconds(1))
                    return try EntriesArchive.data(for: [.blueMoon])
                }
            }

            await store.send(.destination(.presented(.settings(.importFilePicked(.success(Self.url)))))) {
                $0.destination?.modify(\.settings) { $0.destination = .loadingImportFile }
            }
            await store.send(.destination(.dismiss)) {
                $0.destination = nil
            }
            await clock.advance(by: .seconds(1))
        }

        @Test
        func theExportAndImportAvailabilityFollowTheEntries() {
            let loading = Self.state(phase: .loading)
            #expect(!loading.canExportEntries)
            #expect(!loading.canImportEntries)

            let failed = Self.state(phase: .failed)
            #expect(!failed.canExportEntries)
            #expect(!failed.canImportEntries)

            let empty = Self.state(entries: [])
            #expect(!empty.canExportEntries)
            #expect(empty.canImportEntries)

            let populated = Self.state(entries: Entry.mocks)
            #expect(populated.canExportEntries)
            #expect(populated.canImportEntries)
            #expect(!populated.isFileImporterPresented)

            let importing = Self.state(entries: Entry.mocks, destination: .fileImporter)
            #expect(importing.isFileImporterPresented)

            let loadingFile = Self.state(entries: Entry.mocks, destination: .loadingImportFile)
            #expect(loadingFile.canExportEntries)
            #expect(!loadingFile.canImportEntries)
            #expect(!loadingFile.isFileImporterPresented)
        }

        enum ConfirmationButton: CaseIterable, Sendable {
            case deleteAccount
            case signOut

            var action: Settings.Action {
                switch self {
                case .deleteAccount: .deleteAccountButtonTapped
                case .signOut: .signOutButtonTapped
                }
            }

            var alert: AlertState<Settings.Alert> {
                switch self {
                case .deleteAccount: .confirmAccountDeletion
                case .signOut: .confirmSignOut
                }
            }
        }

        private static func state(
            entries: [Entry],
            destination: Settings.Destination.State? = nil
        ) -> Settings.State {
            state(phase: .loaded(IdentifiedArray(uniqueElements: entries)), destination: destination)
        }

        private static func state(
            phase: EntriesPhase,
            destination: Settings.Destination.State? = nil
        ) -> Settings.State {
            Settings.State(destination: destination, entries: SharedReader(value: phase), user: .mock)
        }

        private struct SignOutFailure: Error {}
    }
}
