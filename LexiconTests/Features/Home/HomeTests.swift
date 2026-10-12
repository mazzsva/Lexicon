//
//  HomeTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AuthenticationServices
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
    struct HomeTests {
        // The entries stream and the network monitor start with the scene
        @Test
        func theTaskObservesTheEntriesAndTheConnectivity() async {
            let entries = AsyncThrowingStream<EntriesSnapshot, any Error>.makeStream()
            let connectivity = AsyncStream<Bool>.makeStream()

            let store = TestStore(initialState: Home.State(user: .mock)) {
                Home()
            } withDependencies: {
                $0.entriesClient.entries = { uid in
                    expectNoDifference(uid, User.mock.uid)
                    return entries.stream
                }
                $0.networkMonitorClient.connectivityChanges = { connectivity.stream }
            }

            await store.send(.task)

            entries.continuation.yield(.mock)
            await store.receive(\.entriesUpdated) {
                $0.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
                $0.isSyncing = false
            }

            connectivity.continuation.yield(false)
            await store.receive(\.connectivityChanged, false) {
                $0.isOnline = false
            }

            entries.continuation.finish()
            connectivity.continuation.finish()
            await store.finish()
        }

        // A failed first load has its own state, so the list does not look like an empty account
        @Test
        func aFailedFirstLoadShowsTheEmptyStateAndRetries() async {
            let clock = TestClock()
            let hasFailed = LockIsolated(false)

            let store = TestStore(initialState: Home.State(user: .mock)) {
                Home()
            } withDependencies: {
                $0.continuousClock = clock
                $0.entriesClient.entries = { _ in
                    let isFirstAttempt = hasFailed.withValue { failed -> Bool in
                        defer { failed = true }
                        return !failed
                    }
                    return AsyncThrowingStream { continuation in
                        isFirstAttempt
                            ? continuation.finish(throwing: EntriesFailure())
                            : continuation.finish()
                    }
                }
                $0.networkMonitorClient.connectivityChanges = {
                    AsyncStream { continuation in continuation.finish() }
                }
            }

            await store.send(.task)
            await store.receive(\.entriesStreamFailed) {
                $0.$entries.withLock { $0 = .failed }
            }
            #expect(!store.state.isLoadingFirstEntries)
            expectNoDifference(store.state.emptyState, .failed)

            await clock.advance(by: .seconds(5))
            await store.receive(\.entriesRetryTimerElapsed)
            await store.finish()
        }

        // The entries the user can already read must not disappear on a failure
        @Test
        func aFailedStreamKeepsTheEntriesAndRetriesAfterFiveSeconds() async {
            let clock = TestClock()
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.isSyncing = false

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.continuousClock = clock
                $0.entriesClient.entries = { _ in
                    AsyncThrowingStream { continuation in continuation.finish() }
                }
            }

            await store.send(.entriesStreamFailed) {
                $0.isSyncing = true
            }
            await clock.advance(by: .seconds(4))
            await store.send(.bookmarkFilterButtonTapped) {
                $0.isShowingBookmarkedOnly = true
            }
            await clock.advance(by: .seconds(1))
            await store.receive(\.entriesRetryTimerElapsed)
            await store.finish()
        }

        // Only the first load welcomes the user, and the later ones stay quiet
        @Test
        func aFreshSignInPlaysItsHapticOnlyOnTheFirstLoad() async {
            let state = Home.State(user: .mock, sessionOrigin: .freshSignIn(isNewAccount: false))

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.hapticsClient.success = { playsHaptic() }
                }

                await store.send(.entriesUpdated(.mock)) {
                    $0.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
                    $0.isSyncing = false
                }
                await store.send(.entriesUpdated(.mock))
                await store.finish()
            }
        }

        // The haptic welcomes the user, so it does not depend on the entries
        @Test
        func aFreshSignInPlaysItsHapticEvenWhenTheFirstLoadFails() async {
            let clock = TestClock()
            let entries = AsyncThrowingStream<EntriesSnapshot, any Error>.makeStream()
            let state = Home.State(user: .mock, sessionOrigin: .freshSignIn(isNewAccount: false))

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.continuousClock = clock
                    $0.entriesClient.entries = { _ in entries.stream }
                    $0.hapticsClient.success = { playsHaptic() }
                }

                await store.send(.entriesStreamFailed) {
                    $0.$entries.withLock { $0 = .failed }
                }
                #expect(!store.state.isLoadingFirstEntries)

                await clock.advance(by: .seconds(5))
                await store.receive(\.entriesRetryTimerElapsed)
                entries.continuation.yield(.mock)
                entries.continuation.finish()
                await store.receive(\.entriesUpdated) {
                    $0.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
                    $0.isSyncing = false
                }
                await store.finish()
            }
        }

        // A sync cannot finish without a network, so the offline status wins
        @Test
        func theConnectivityDrivesTheSyncStatus() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.isSyncing = false

            let store = TestStore(initialState: state) {
                Home()
            }

            expectNoDifference(store.state.syncStatus, .synced)

            await store.send(.connectivityChanged(false)) {
                $0.isOnline = false
            }
            expectNoDifference(store.state.syncStatus, .offline)

            await store.send(.entriesUpdated(.syncing)) {
                $0.isSyncing = true
            }
            expectNoDifference(store.state.syncStatus, .offline)

            await store.send(.connectivityChanged(true)) {
                $0.isOnline = true
            }
            expectNoDifference(store.state.syncStatus, .syncing)
        }

        // Blue moon is the only mock entry with a bookmark
        @Test
        func theBookmarkFilterShowsOnlyBookmarkedEntries() async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.bookmarkFilterButtonTapped) {
                $0.isShowingBookmarkedOnly = true
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.blueMoon])

            await store.send(.bookmarkFilterButtonTapped) {
                $0.isShowingBookmarkedOnly = false
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), Entry.mocks)
        }

        // The filter button disappears with the last entry, so the filter must clear itself
        @Test
        func anEmptyListClearsTheBookmarkFilter() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.isShowingBookmarkedOnly = true

            let store = TestStore(initialState: state) {
                Home()
            }

            #expect(store.state.canFilterBookmarks)

            await store.send(.entriesUpdated(.empty)) {
                $0.$entries.withLock { $0 = .loaded([]) }
                $0.isShowingBookmarkedOnly = false
                $0.isSyncing = false
            }
            #expect(!store.state.canFilterBookmarks)
        }

        // The user can remember the meaning of an entry but not its term
        @Test
        func theSearchTextMatchesTheTermsAndTheDefinitions() async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.binding(.set(\.searchText, "candle"))) {
                $0.searchText = "candle"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.burningCandle])

            await store.send(.binding(.set(\.searchText, "easiest"))) {
                $0.searchText = "easiest"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.lowHangingFruit])
        }

        // The search runs inside the filter, so an unbookmarked match stays hidden
        @Test
        func theSearchTextAndTheBookmarkFilterApplyTogether() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.isShowingBookmarkedOnly = true

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.binding(.set(\.searchText, "candle"))) {
                $0.searchText = "candle"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [])

            await store.send(.binding(.set(\.searchText, "moon"))) {
                $0.searchText = "moon"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.blueMoon])
        }

        // An empty list has three reasons, and each one needs its own message
        @Test
        func theEntriesPhaseDrivesTheDerivedState() {
            var state = Home.State(user: .mock)
            #expect(state.isLoadingFirstEntries)
            #expect(!state.canCreateEntries)
            expectNoDifference(state.emptyState, nil)
            expectNoDifference(state.entryCount, nil)
            expectNoDifference(state.filteredEntries.map(\.wrappedValue), [])

            state.$entries.withLock { $0 = .failed }
            #expect(!state.isLoadingFirstEntries)
            #expect(!state.canCreateEntries)
            expectNoDifference(state.emptyState, .failed)
            expectNoDifference(state.entryCount, nil)
            expectNoDifference(state.filteredEntries.map(\.wrappedValue), [])

            state.$entries.withLock { $0 = .loaded([]) }
            #expect(state.canCreateEntries)
            expectNoDifference(state.emptyState, .entries)
            expectNoDifference(state.entryCount, 0)

            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            expectNoDifference(state.emptyState, nil)
            expectNoDifference(state.entryCount, 3)

            state.$entries.withLock {
                $0 = .loaded(IdentifiedArray(uniqueElements: [Entry.burningCandle, Entry.lowHangingFruit]))
            }
            state.isShowingBookmarkedOnly = true
            expectNoDifference(state.emptyState, .bookmarks)
            expectNoDifference(state.entryCount, 2)

            state.isShowingBookmarkedOnly = false
            state.searchText = "nothing matches this"
            expectNoDifference(state.emptyState, .search)
            expectNoDifference(state.entryCount, 2)
        }

        // A form without an entry creates one, and a form with an entry edits it
        @Test
        func theNewEntryButtonOpensAnEmptyForm() async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded([]) }

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.newEntryButtonTapped) {
                $0.destination = .createEntry(EntryForm.State())
            }
        }

        @Test(arguments: [EntriesPhase.loading, .failed])
        func theNewEntryButtonDoesNothingUntilTheEntriesLoad(phase: EntriesPhase) async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = phase }

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.newEntryButtonTapped)
        }

        // The form only reports the entry, and home writes it to the server
        @Test
        func creatingAnEntrySavesItAndClosesTheForm() async throws {
            let now = Date(timeIntervalSince1970: 1_751_000_000)
            let created = try Entry(
                createdAt: now,
                definition: "The easiest wins, taken first.",
                id: UUID(0),
                isBookmarked: false,
                term: "Low-hanging fruit"
            )

            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.destination = .createEntry(EntryForm.State())

            await confirmation("Saves the entry") { savesEntry in
                await confirmation("Plays the success haptic") { playsHaptic in
                    let store = TestStore(initialState: state) {
                        Home()
                    } withDependencies: {
                        $0.date.now = now
                        $0.entriesClient.create = { entry, uid in
                            expectNoDifference(entry, created)
                            expectNoDifference(uid, User.mock.uid)
                            savesEntry()
                        }
                        $0.hapticsClient.success = { playsHaptic() }
                        $0.uuid = .incrementing
                    }

                    await store.send(
                        .destination(.presented(.createEntry(.binding(.set(\.term, "  Low-hanging fruit  ")))))
                    ) {
                        $0.destination?.modify(\.createEntry) { $0.term = "  Low-hanging fruit  " }
                    }
                    await store.send(
                        .destination(.presented(.createEntry(.binding(.set(\.definition, created.definition)))))
                    ) {
                        $0.destination?.modify(\.createEntry) { $0.definition = created.definition }
                    }
                    await store.send(.destination(.presented(.createEntry(.saveButtonTapped))))
                    await store.receive(\.destination.presented.createEntry.delegate.didSubmit, created) {
                        $0.destination = nil
                    }
                    await store.finish()
                }
            }
        }

        // Home reads the delegate actions only, and the detail keeps the rest
        @Test
        func aNonDelegateDetailActionIsHandledByTheDetail() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.path(.element(id: detailID, action: .deleteButtonTapped))) {
                $0.path[id: detailID]?.destination = .alert(.confirmDeletion)
            }
        }

        // The detail stays on screen because it reads the entry from the shared state
        @Test
        func updatingFromTheDetailSavesTheEntry() async {
            var bookmarked = Entry.burningCandle
            bookmarked.isBookmarked = true

            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .burningCandle)))
            let detailID = Array(state.path.ids)[0]

            await confirmation("Saves the entry") { savesEntry in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.entriesClient.update = { [bookmarked] entry, uid in
                        expectNoDifference(entry, bookmarked)
                        expectNoDifference(uid, User.mock.uid)
                        savesEntry()
                    }
                }

                await store.send(
                    .path(.element(id: detailID, action: .delegate(.didUpdate(bookmarked))))
                )
                await store.finish()
            }
        }

        // The save leaves no trace on screen, so an alert must report the failure
        @Test
        func aFailedUpdateShowsAnAlert() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.update = { _, _ in throw EntriesFailure() }
            }

            await store.send(
                .path(.element(id: detailID, action: .delegate(.didUpdate(.blueMoon))))
            )
            await store.receive(\.entrySaveFailed) {
                $0.destination = .alert(.failed(.entrySave))
            }
        }

        @Test
        func aFailedCreationShowsAnAlert() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.destination = .createEntry(EntryForm.State())

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.create = { _, _ in throw EntriesFailure() }
                $0.hapticsClient.success = {}
            }

            await store.send(.destination(.presented(.createEntry(.delegate(.didSubmit(.blueMoon)))))) {
                $0.destination = nil
            }
            await store.receive(\.entrySaveFailed) {
                $0.destination = .alert(.failed(.entrySave))
            }
        }

        // The detail leaves the stack first because its entry is about to disappear
        @Test
        func deletingFromTheDetailPopsBackAndDeletesTheEntry() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            await confirmation("Deletes the entry") { deletesEntry in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.entriesClient.delete = { id, uid in
                        expectNoDifference(id, Entry.blueMoon.id)
                        expectNoDifference(uid, User.mock.uid)
                        deletesEntry()
                    }
                    $0.hapticsClient.warning = {}
                }

                await store.send(
                    .path(.element(id: detailID, action: .delegate(.didDelete(Entry.blueMoon.id))))
                ) {
                    $0.path.pop(from: detailID)
                }
                await store.finish()
            }
        }

        // The detail pops before the delete reaches the server, so an alert must report the failure
        @Test
        func aFailedDeletionShowsAnAlert() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.delete = { _, _ in throw EntriesFailure() }
                $0.hapticsClient.warning = {}
            }

            await store.send(
                .path(.element(id: detailID, action: .delegate(.didDelete(Entry.blueMoon.id))))
            ) {
                $0.path.pop(from: detailID)
            }
            await store.receive(\.entryDeleteFailed) {
                $0.destination = .alert(.failed(.entryDelete))
            }
        }

        // A different device can delete the entry while its detail is on screen
        @Test
        func aDeletedEntryPopsItsDetail() async {
            let remaining = [Entry.burningCandle, Entry.lowHangingFruit]
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.entriesUpdated(EntriesSnapshot(entries: remaining, isSyncing: false))) {
                $0.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: remaining)) }
                $0.isSyncing = false
                $0.path.pop(from: detailID)
            }
        }

        // A snapshot that still holds the entry must not disturb the stack
        @Test
        func aSurvivingEntryKeepsItsDetail() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            state.isSyncing = false

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.entriesUpdated(.mock))
        }

        // The settings need the user, and home is the scene that holds it
        @Test
        func theSettingsButtonOpensTheSettings() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.isShowingBookmarkedOnly = true
            state.searchText = "moon"

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.settingsButtonTapped) {
                $0.destination = .settings(
                    Settings.State(
                        entries: SharedReader(value: .loaded(IdentifiedArray(uniqueElements: Entry.mocks))),
                        user: .mock
                    )
                )
            }
        }

        @Test
        func theSettingsOpenWithoutEntriesWhenTheFirstLoadFails() async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .failed }

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.settingsButtonTapped) {
                $0.destination = .settings(Settings.State(entries: SharedReader(value: .failed), user: .mock))
            }
        }

        @Test
        func theSettingsFollowTheEntriesWhileTheyAreOpen() async {
            let state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded([]) }

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.settingsButtonTapped) {
                $0.destination = .settings(Settings.State(entries: SharedReader($0.$entries), user: .mock))
            }
            await store.send(.entriesUpdated(.mock)) {
                $0.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
                $0.isSyncing = false
            }
            expectNoDifference(
                store.state.destination?.settings?.entries,
                .loaded(IdentifiedArray(uniqueElements: Entry.mocks))
            )
        }

        @Test
        func importingClosesTheSettingsAndSavesTheImportedEntries() async throws {
            let imported = [
                try Entry(
                    createdAt: Date(timeIntervalSince1970: 1_751_000_000),
                    definition: "To start a conversation.",
                    id: UUID(5),
                    isBookmarked: false,
                    term: "Break the ice"
                )
            ]
            let saved = LockIsolated<[Entry]?>(nil)

            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            state.destination = .settings(Settings.State(entries: SharedReader(state.$entries), user: .mock))

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.entriesClient.createAll = { entries, uid in
                        expectNoDifference(uid, User.mock.uid)
                        saved.setValue(entries)
                    }
                    $0.hapticsClient.success = { playsHaptic() }
                }

                await store.send(.destination(.presented(.settings(.delegate(.didImport(imported)))))) {
                    $0.destination = nil
                }
                await store.finish()
            }
            expectNoDifference(saved.value, imported)
        }

        @Test
        func anExportRestoresEveryFieldIntoAnEmptyAccount() async throws {
            let user = User(email: nil, uid: "other-uid")
            let entries =
                try [
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
            let imported = try entries.enumerated()
                .map { offset, entry in
                    try Entry(
                        content: entry.content,
                        createdAt: entry.createdAt,
                        id: UUID(100 + offset),
                        isBookmarked: entry.isBookmarked
                    )
                }
            let entriesImport = EntriesArchive.Import(duplicateCount: 0, entries: imported, invalidCount: 0)
            let nextID = LockIsolated(100)
            let saved = LockIsolated<[Entry]?>(nil)

            var state = Home.State(user: user)
            state.$entries.withLock { $0 = .loaded([]) }
            state.isSyncing = false

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.date.now = Date(timeIntervalSince1970: 1_751_000_000)
                $0.entriesClient.createAll = { entries, uid in
                    expectNoDifference(uid, user.uid)
                    saved.setValue(entries)
                }
                $0.fileClient.read = { _, _ in try await EntriesArchive.Export(entries: entries).exported(as: .json) }
                $0.hapticsClient.success = {}
                $0.uuid = UUIDGenerator {
                    nextID.withValue { id in
                        defer { id += 1 }
                        return UUID(id)
                    }
                }
            }

            await store.send(.settingsButtonTapped) {
                $0.destination = .settings(Settings.State(entries: SharedReader(value: .loaded([])), user: user))
            }
            await store.send(
                .destination(.presented(.settings(.importFilePicked(.success(URL(filePath: "/a.json"))))))
            ) {
                $0.destination?.modify(\.settings) { $0.destination = .loadingImportFile }
            }
            await store.receive(\.destination.presented.settings.importFileLoaded) {
                $0.destination?.modify(\.settings) { $0.destination = .alert(.confirmImport(entriesImport)) }
            }
            await store.send(
                .destination(.presented(.settings(.destination(.presented(.alert(.confirmImport(imported)))))))
            ) {
                $0.destination?.modify(\.settings) { $0.destination = nil }
            }
            await store.receive(\.destination.presented.settings.delegate.didImport, imported) {
                $0.destination = nil
            }
            await store.finish()
            expectNoDifference(saved.value, imported)
        }

        @Test
        func aFailedImportShowsAnAlert() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded([]) }
            state.destination = .settings(Settings.State(entries: SharedReader(state.$entries), user: .mock))

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.createAll = { _, _ in throw EntriesFailure() }
                $0.hapticsClient.success = {}
            }

            await store.send(.destination(.presented(.settings(.delegate(.didImport([.blueMoon])))))) {
                $0.destination = nil
            }
            await store.receive(\.entriesImportFailed) {
                $0.destination = .alert(.failed(.entryImport))
            }
        }

        @Test(arguments: Home.Failure.allCases)
        func aFailureWaitsForThePresentedDestinationToClose(failure: Home.Failure) async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.destination = .createEntry(EntryForm.State())

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(Self.failedAction(failure)) {
                $0.pendingFailures = [failure]
            }
            await store.send(.destination(.dismiss)) {
                $0.destination = .alert(.failed(failure))
                $0.pendingFailures = []
            }
        }

        @Test
        func aFailedDeletionWaitsForTheDetailAlertToClose() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.path(.element(id: detailID, action: .deleteButtonTapped))) {
                $0.path[id: detailID]?.destination = .alert(.confirmDeletion)
            }
            await store.send(.entryDeleteFailed(Entry.burningCandle.id, EntriesFailure())) {
                $0.pendingFailures = [.entryDelete]
            }
            await store.send(.path(.element(id: detailID, action: .destination(.dismiss)))) {
                $0.destination = .alert(.failed(.entryDelete))
                $0.pendingFailures = []
                $0.path[id: detailID]?.destination = nil
            }
        }

        @Test
        func theFailuresThatWaitForTheSettingsShowOneAfterTheOther() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.destination = .settings(Settings.State(entries: SharedReader(state.$entries), user: .mock))

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.entrySaveFailed(Entry.blueMoon.id, EntriesFailure())) {
                $0.pendingFailures = [.entrySave]
            }
            await store.send(.entrySaveFailed(Entry.burningCandle.id, EntriesFailure()))
            await store.send(.entryDeleteFailed(Entry.lowHangingFruit.id, EntriesFailure())) {
                $0.pendingFailures = [.entryDelete, .entrySave]
            }
            await store.send(.destination(.dismiss)) {
                $0.destination = .alert(.failed(.entryDelete))
                $0.pendingFailures = [.entrySave]
            }
            await store.send(.destination(.dismiss)) {
                $0.destination = .alert(.failed(.entrySave))
                $0.pendingFailures = []
            }
            await store.send(.destination(.dismiss)) {
                $0.destination = nil
            }
        }

        @Test
        func confirmingTheAccountDeletionClosesTheSettingsAndCancelingReopensThem() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.destination = .settings(
                Settings.State(
                    destination: .alert(.confirmAccountDeletion),
                    entries: SharedReader(state.$entries),
                    user: .mock
                )
            )

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.signInWithAppleClient.requestCredential = { throw ASAuthorizationError(.canceled) }
            }

            await store.send(
                .destination(.presented(.settings(.destination(.presented(.alert(.confirmAccountDeletion))))))
            ) {
                $0.destination?.modify(\.settings) { $0.destination = nil }
            }
            await store.receive(\.destination.presented.settings.delegate.didConfirmAccountDeletion) {
                $0.destination = .accountDeletion(AccountDeletion.State(uid: User.mock.uid))
            }
            await store.receive(\.destination.presented.accountDeletion.deletionConfirmed)
            await store.receive(\.destination.presented.accountDeletion.deletionFailed)
            await store.receive(\.destination.presented.accountDeletion.delegate.didCancel) {
                $0.destination = .settings(
                    Settings.State(
                        entries: SharedReader(value: .loaded(IdentifiedArray(uniqueElements: Entry.mocks))),
                        user: .mock
                    )
                )
            }
            await store.finish()
        }

        @Test
        func aFailureWaitsForTheAccountDeletionToEnd() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.destination = .accountDeletion(AccountDeletion.State(step: .deleting, uid: User.mock.uid))

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.entrySaveFailed(Entry.blueMoon.id, EntriesFailure())) {
                $0.pendingFailures = [.entrySave]
            }
            await store.send(.destination(.presented(.accountDeletion(.delegate(.didFail(.notFullyDeleted)))))) {
                $0.destination = .settings(
                    Settings.State(
                        destination: .alert(.accountDeletionFailed(.notFullyDeleted)),
                        entries: SharedReader(value: .loaded(IdentifiedArray(uniqueElements: Entry.mocks))),
                        user: .mock
                    )
                )
            }
            await store.send(.destination(.dismiss)) {
                $0.destination = .alert(.failed(.entrySave))
                $0.pendingFailures = []
            }
        }

        private static func failedAction(_ failure: Home.Failure) -> Home.Action {
            switch failure {
            case .entryDelete: .entryDeleteFailed(Entry.blueMoon.id, EntriesFailure())
            case .entryImport: .entriesImportFailed(EntriesFailure())
            case .entrySave: .entrySaveFailed(Entry.blueMoon.id, EntriesFailure())
            }
        }

        private struct EntriesFailure: Error {}
    }
}
