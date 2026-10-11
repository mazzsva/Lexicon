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

        @Test(arguments: [0, 1, 3], [0, 1, 3])
        func theConfirmationCountsTheSkippedEntries(duplicateCount: Int, invalidCount: Int) async {
            for newCount in [0, 1, 3] {
                let newEntries = (0 ..< newCount)
                    .map { index in
                        Entry(
                            createdAt: Self.now,
                            definition: "",
                            id: UUID(100 + index),
                            isBookmarked: false,
                            term: "New \(index)"
                        )
                    }
                let records =
                    newEntries.map(Self.record)
                    + Entry.mocks.prefix(duplicateCount).map(Self.record)
                    + (0 ..< invalidCount).map { _ in EntriesArchive.Record(term: "") }
                let expected: AlertState<Settings.Alert> =
                    if newCount > 0 {
                        .confirmImport(
                            newEntries,
                            duplicateCount: min(duplicateCount, Entry.mocks.count),
                            invalidCount: invalidCount
                        )
                    } else if duplicateCount > 0 {
                        .importHasOnlyDuplicates
                    } else {
                        .importHasNoEntries
                    }

                let store = TestStore(initialState: Self.state(entries: Entry.mocks)) {
                    Settings()
                } withDependencies: {
                    $0.date.now = Self.now
                }

                await store.send(.importFileLoaded(.success(records))) {
                    $0.alert = expected
                }
            }
        }

        @Test
        func theConfirmationTextNamesEachKindOfSkippedEntry() {
            let both = AlertState<Settings.Alert>.confirmImport([.blueMoon], duplicateCount: 3, invalidCount: 2)
            expectNoDifference(both.title, TextState("Import ^[\(1) Entry](inflect: true)?"))
            expectNoDifference(
                both.message,
                TextState("^[\(3) entry](inflect: true) already in Lexicon will be skipped.")
                    + TextState(verbatim: " ")
                    + TextState("^[\(2) entry](inflect: true) can't be imported and will be skipped.")
            )
            expectNoDifference(
                AlertState<Settings.Alert>.confirmImport(Entry.mocks, duplicateCount: 0, invalidCount: 0).title,
                TextState("Import ^[\(3) Entry](inflect: true)?")
            )
        }

        @Test
        func aValidCopyAfterAnInvalidCopyWithTheSameIDIsImported() async {
            let records = [
                EntriesArchive.Record(id: UUID(5), term: "  "),
                EntriesArchive.Record(id: UUID(5), term: "Break the ice"),
            ]
            let expected = Entry(
                createdAt: Self.now,
                definition: "",
                id: UUID(5),
                isBookmarked: false,
                term: "Break the ice"
            )

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.date.now = Self.now
            }

            await store.send(.importFileLoaded(.success(records))) {
                $0.alert = .confirmImport([expected], duplicateCount: 0, invalidCount: 1)
            }
        }

        @Test
        func everyCopyOfAnExistingEntryIsSkipped() async {
            var edited = Self.record(.blueMoon)
            edited.term = "Edited in the file"

            let store = TestStore(initialState: Self.state(entries: Entry.mocks)) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([Self.record(.blueMoon), edited]))) {
                $0.alert = .importHasOnlyDuplicates
            }
        }

        @Test
        func theFirstCopyOfANewEntryWins() async {
            let first = Entry(
                createdAt: Self.now,
                definition: "First",
                id: UUID(5),
                isBookmarked: true,
                term: "Break the ice"
            )
            var second = Self.record(first)
            second.definition = "Second"

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([Self.record(first), second]))) {
                $0.alert = .confirmImport([first], duplicateCount: 0, invalidCount: 0)
            }
        }

        @Test
        func eachRecordWithoutAnIDGetsItsOwnID() async {
            let records = ["One", "Two", "Three"].map { EntriesArchive.Record(term: $0) }
            let expected = ["One", "Two", "Three"].enumerated()
                .map { index, term in
                    Entry(createdAt: Self.now, definition: "", id: UUID(index), isBookmarked: false, term: term)
                }

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.date.now = Self.now
                $0.uuid = .incrementing
            }

            await store.send(.importFileLoaded(.success(records))) {
                $0.alert = .confirmImport(expected, duplicateCount: 0, invalidCount: 0)
            }
        }

        @Test
        func blankTermsAreInvalidAndTheTextIsTrimmed() async {
            let records = [
                EntriesArchive.Record(id: UUID(1), term: " "),
                EntriesArchive.Record(id: UUID(2), term: "\n\n"),
                EntriesArchive.Record(id: UUID(3), term: "\t \r\n"),
                EntriesArchive.Record(definition: "Orphan", id: UUID(4), term: nil),
                EntriesArchive.Record(definition: " \n ", id: UUID(5), term: "\n  Break  the ice \t"),
                EntriesArchive.Record(definition: "\n To start a conversation. \n", id: UUID(6), term: "Spill"),
            ]
            let expected = [
                Entry(createdAt: Self.now, definition: "", id: UUID(5), isBookmarked: false, term: "Break  the ice"),
                Entry(
                    createdAt: Self.now,
                    definition: "To start a conversation.",
                    id: UUID(6),
                    isBookmarked: false,
                    term: "Spill"
                ),
            ]

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.date.now = Self.now
            }

            await store.send(.importFileLoaded(.success(records))) {
                $0.alert = .confirmImport(expected, duplicateCount: 0, invalidCount: 4)
            }
        }

        @Test
        func theEntriesKeepTheOrderOfTheFile() async {
            let entries = (0 ..< 20).reversed()
                .map { index in
                    Entry(
                        createdAt: Date(timeIntervalSince1970: Double(index)),
                        definition: "",
                        id: UUID(index),
                        isBookmarked: false,
                        term: "Term \(index)"
                    )
                }

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success(entries.map(Self.record)))) {
                $0.alert = .confirmImport(entries, duplicateCount: 0, invalidCount: 0)
            }
        }

        @Test
        func tenThousandRecordsLoadQuickly() async {
            let entries = (0 ..< 10_000)
                .map { index in
                    Entry(
                        createdAt: Self.now, definition: "", id: UUID(index), isBookmarked: false, term: "Term \(index)"
                    )
                }
            let existing = Array(entries.prefix(5_000))

            let store = TestStore(initialState: Self.state(entries: existing)) {
                Settings()
            }

            let start = ContinuousClock.now
            await store.send(.importFileLoaded(.success(entries.map(Self.record)))) {
                $0.alert = .confirmImport(Array(entries.dropFirst(5_000)), duplicateCount: 5_000, invalidCount: 0)
            }
            #expect(ContinuousClock.now - start < .seconds(5))
        }

        @Test
        func theDuplicatesUseTheEntriesAtLoadTime() async {
            let entries = Shared<IdentifiedArrayOf<Entry>?>(value: [])

            let store = TestStore(
                initialState: Settings.State(entries: SharedReader(entries), isEntriesSynced: true, user: .mock)
            ) {
                Settings()
            }

            entries.withLock { $0 = [.blueMoon] }
            await store.send(.importFileLoaded(.success([Self.record(.blueMoon)]))) {
                $0.alert = .importHasOnlyDuplicates
            }
        }

        @Test
        func aLoadBeforeTheFirstEntriesIsIgnored() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([Self.record(.blueMoon)])))
        }

        @Test
        func theImportButtonIsIgnoredDuringAnAccountDeletion() async {
            var state = Self.state(entries: Entry.mocks)
            state.deletionStep = .deleting

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.importEntriesButtonTapped)
            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
        }

        @Test
        func aLoadThatEndsDuringAnAccountDeletionIsIgnored() async {
            var state = Self.state(entries: Entry.mocks)
            state.deletionStep = .reauthenticating

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([EntriesArchive.Record(id: UUID(5), term: "New")])))
            await store.send(.importFileLoaded(.failure(EntriesArchive.Error.invalid)))
        }

        @Test
        func aConfirmationDuringAnAccountDeletionDoesNotImport() async {
            var state = Self.state(entries: Entry.mocks)
            state.alert = .confirmImport([.blueMoon], duplicateCount: 0, invalidCount: 0)
            state.deletionStep = .deleting

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.alert(.presented(.confirmImport([.blueMoon])))) {
                $0.alert = nil
            }
        }

        @Test
        func anAccountDeletionCancelsTheLoad() async {
            let clock = TestClock()

            let store = TestStore(initialState: Self.state(entries: Entry.mocks)) {
                Settings()
            } withDependencies: {
                $0.continuousClock = clock
                $0.fileClient.read = { _, _ in
                    try await clock.sleep(for: .seconds(1))
                    return try EntriesArchive.data(for: [.blueMoon])
                }
                $0.signInWithAppleClient.requestCredential = { throw DeletionFailure() }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.send(.deleteAccountButtonTapped) {
                $0.alert = .confirmAccountDeletion
            }
            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.accountDeletionFailed) {
                $0.alert = .accountDeletionFailed
                $0.deletionStep = nil
            }
            await clock.advance(by: .seconds(1))
        }

        @Test
        func aSignOutCancelsTheLoad() async {
            let clock = TestClock()

            let store = TestStore(initialState: Self.state(entries: Entry.mocks)) {
                Settings()
            } withDependencies: {
                $0.authClient.signOut = {}
                $0.fileClient.read = { _, _ in
                    try await clock.sleep(for: .seconds(1))
                    return try EntriesArchive.data(for: [.blueMoon])
                }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.send(.signOutButtonTapped) {
                $0.alert = .confirmSignOut
            }
            await store.send(.alert(.presented(.confirmSignOut))) {
                $0.alert = nil
            }
            await clock.advance(by: .seconds(1))
            await store.finish()
        }

        @Test
        func aLoadThatEndsAfterTheSyncStopsAsksToSync() async {
            var state = Self.state(entries: Entry.mocks)
            state.isEntriesSynced = false

            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in
                    try EntriesArchive.data(for: [.blueMoon])
                }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .importNeedsSync
            }
        }

        @Test
        func aSecondPickReplacesTheFirstLoad() async {
            let clock = TestClock()
            let first = URL(filePath: "/First.json")
            let second = URL(filePath: "/Second.json")
            let secondEntry = Entry(
                createdAt: Self.now,
                definition: "",
                id: UUID(9),
                isBookmarked: false,
                term: "Second"
            )

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { url, _ in
                    if url == first {
                        try await clock.sleep(for: .seconds(2))
                        return try EntriesArchive.data(for: [.blueMoon])
                    }
                    try await clock.sleep(for: .seconds(1))
                    return try EntriesArchive.data(for: [secondEntry])
                }
            }

            await store.send(.importFilePicked(.success(first)))
            await store.send(.importFilePicked(.success(second)))
            await clock.advance(by: .seconds(1))
            await store.receive(\.importFileLoaded) {
                $0.alert = .confirmImport([secondEntry], duplicateCount: 0, invalidCount: 0)
            }
            await clock.advance(by: .seconds(1))
        }

        @Test
        func dismissingTheConfirmationDoesNotImport() async {
            var state = Self.state(entries: [])
            state.alert = .confirmImport([.blueMoon], duplicateCount: 0, invalidCount: 0)

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.alert(.dismiss)) {
                $0.alert = nil
            }
        }

        @Test
        func closingTheSettingsDuringTheLoadDropsTheResult() async {
            let clock = TestClock()
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = [] }
            state.destination = .settings(Settings.State(entries: SharedReader(state.$entries), user: .mock))

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.fileClient.read = { _, _ in
                    try await clock.sleep(for: .seconds(1))
                    return try EntriesArchive.data(for: [.blueMoon])
                }
            }

            await store.send(.destination(.presented(.settings(.importFilePicked(.success(URL(filePath: "/E.json")))))))
            await store.send(.destination(.dismiss)) {
                $0.destination = nil
            }
            await clock.advance(by: .seconds(1))
        }

        @Test
        func theExportAndImportAvailabilityFollowTheEntries() {
            let loading = Settings.State(user: .mock)
            #expect(!loading.canExportEntries)
            #expect(!loading.canImportEntries)

            let empty = Self.state(entries: [])
            #expect(!empty.canExportEntries)
            #expect(empty.canImportEntries)

            let populated = Self.state(entries: Entry.mocks)
            #expect(populated.canExportEntries)
            #expect(populated.canImportEntries)
        }

        @Test
        func anEntryAtTheSizeLimitImportsAndOneByteMoreIsSkipped() async {
            let atLimit = Self.entry(id: 1, term: "T", definition: Self.text(utf8Count: Self.definitionLimit))
            let overLimit = Self.entry(id: 2, term: "T", definition: Self.text(utf8Count: Self.definitionLimit + 1))
            #expect(atLimit.estimatedDocumentSize == Entry.maximumDocumentSize)
            #expect(overLimit.estimatedDocumentSize == Entry.maximumDocumentSize + 1)

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([atLimit, overLimit].map(Self.record)))) {
                $0.alert = .confirmImport([atLimit], duplicateCount: 0, invalidCount: 1)
            }
        }

        @Test
        func theSizeLimitCountsUTF8BytesNotCharacters() async {
            let emojiCount = Self.definitionLimit / 4
            let underLimit = Self.entry(id: 1, term: "T", definition: String(repeating: "😀", count: emojiCount))
            let overLimit = Self.entry(id: 2, term: "T", definition: String(repeating: "😀", count: emojiCount + 1))
            #expect(overLimit.definition.count < Self.definitionLimit)
            #expect(underLimit.estimatedDocumentSize <= Entry.maximumDocumentSize)
            #expect(overLimit.estimatedDocumentSize > Entry.maximumDocumentSize)

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([underLimit, overLimit].map(Self.record)))) {
                $0.alert = .confirmImport([underLimit], duplicateCount: 0, invalidCount: 1)
            }
        }

        @Test
        func aLargeTermOrALargeDefinitionIsSkipped() async {
            let largeTerm = Self.entry(id: 1, term: Self.text(utf8Count: 1_000_000), definition: "")
            let largeDefinition = Self.entry(id: 2, term: "T", definition: Self.text(utf8Count: 1_000_000))
            let small = Self.entry(id: 3, term: "Break the ice", definition: "To start a conversation.")

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([largeTerm, largeDefinition, small].map(Self.record)))) {
                $0.alert = .confirmImport([small], duplicateCount: 0, invalidCount: 2)
            }
        }

        @Test
        func theSizeLimitAppliesAfterTheTextIsTrimmed() async {
            let trimmed = Self.entry(id: 1, term: "T", definition: Self.text(utf8Count: Self.definitionLimit))
            var record = Self.record(trimmed)
            record.definition = "\n   " + trimmed.definition + "   \n"

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([record]))) {
                $0.alert = .confirmImport([trimmed], duplicateCount: 0, invalidCount: 0)
            }
        }

        @Test
        func aLargeCopyDoesNotHideALaterValidCopyWithTheSameID() async {
            let large = Self.entry(id: 1, term: "T", definition: Self.text(utf8Count: 2_000_000))
            let valid = Self.entry(id: 1, term: "Break the ice", definition: "To start a conversation.")

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([large, valid].map(Self.record)))) {
                $0.alert = .confirmImport([valid], duplicateCount: 0, invalidCount: 1)
            }
        }

        @Test
        func aLargeCopyOfAnEntryInLexiconCountsAsADuplicate() async {
            var large = Entry.blueMoon
            large.definition = Self.text(utf8Count: 2_000_000)

            let store = TestStore(initialState: Self.state(entries: Entry.mocks)) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([Self.record(large)]))) {
                $0.alert = .importHasOnlyDuplicates
            }
        }

        @Test
        func aFileWithOnlyLargeEntriesHasNothingToImport() async {
            let large = Self.entry(id: 1, term: "T", definition: Self.text(utf8Count: 2_000_000))

            let store = TestStore(initialState: Self.state(entries: [])) {
                Settings()
            }

            await store.send(.importFileLoaded(.success([Self.record(large)]))) {
                $0.alert = .importHasNoEntries
            }
        }

        private static let definitionLimit =
            Entry.maximumDocumentSize - entry(id: 0, term: "T", definition: "").estimatedDocumentSize

        private static func entry(id: Int, term: String, definition: String) -> Entry {
            Entry(createdAt: now, definition: definition, id: UUID(id), isBookmarked: false, term: term)
        }

        private static func text(utf8Count: Int) -> String {
            String(repeating: "a", count: utf8Count)
        }

        private static func record(_ entry: Entry) -> EntriesArchive.Record {
            EntriesArchive.Record(
                createdAt: entry.createdAt,
                definition: entry.definition,
                id: entry.id,
                isBookmarked: entry.isBookmarked,
                term: entry.term
            )
        }

        private static func state(entries: [Entry]) -> Settings.State {
            Settings.State(
                entries: SharedReader(value: IdentifiedArray(uniqueElements: entries)),
                isEntriesSynced: true,
                user: .mock
            )
        }

        private struct DeletionFailure: Error {}
    }
}
