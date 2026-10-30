//
//  HomeTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AuthenticationServices
import ComposableArchitecture
import CustomDump
import Foundation
import Testing

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

            await clock.advance(by: Home.entriesRetryDelay)
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

            await store.send(.entriesStreamFailed(EntriesFailure())) {
                $0.isSyncing = true
            }
            await clock.advance(by: Home.entriesRetryDelay - .seconds(1))
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

                await store.send(.entriesStreamFailed(EntriesFailure())) {
                    $0.$entries.withLock { $0 = .failed }
                }
                #expect(!store.state.isLoadingFirstEntries)

                await clock.advance(by: Home.entriesRetryDelay)
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

        // Burning candle is the only mock entry with a bookmark
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
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.burningCandle])

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

            await store.send(.binding(.set(\.searchText, "answer"))) {
                $0.searchText = "answer"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.wrongTree])
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

            await store.send(.binding(.set(\.searchText, "moon"))) {
                $0.searchText = "moon"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [])

            await store.send(.binding(.set(\.searchText, "candle"))) {
                $0.searchText = "candle"
            }
            expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.burningCandle])
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
            expectNoDifference(state.entryCount, 5)

            state.$entries.withLock {
                $0 = .loaded(IdentifiedArray(uniqueElements: [Entry.blueMoon, Entry.wrongTree]))
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
                    await store.receive(\.destination.presented.createEntry.delegate.didCreate, created) {
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
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .rabbitHole)))
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            await confirmation("Saves the entry") { savesEntry in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.entriesClient.updateBookmark = { id, isBookmarked, uid in
                        expectNoDifference(id, Entry.rabbitHole.id)
                        #expect(isBookmarked)
                        expectNoDifference(uid, User.mock.uid)
                        savesEntry()
                    }
                }

                await store.send(
                    .path(.element(id: detailID, action: .delegate(.didChangeBookmark(true))))
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
                $0.entriesClient.updateContent = { _, _, _ in throw EntriesFailure() }
            }

            await store.send(
                .path(.element(id: detailID, action: .delegate(.didUpdate(Entry.blueMoon.content))))
            )
            await store.receive(\.entrySaveFailed) {
                $0.destination = .alert(.failed(.entrySave))
            }
        }

        @Test
        func editingFromTheDetailSavesOnlyTheContent() async throws {
            let edited = try Entry.Content(term: Entry.blueMoon.term, definition: "A rare event.")

            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .burningCandle)))
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[1]

            await confirmation("Saves the content") { savesContent in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.entriesClient.updateContent = { id, content, uid in
                        expectNoDifference(id, Entry.blueMoon.id)
                        expectNoDifference(content, edited)
                        expectNoDifference(uid, User.mock.uid)
                        savesContent()
                    }
                }

                await store.send(.path(.element(id: detailID, action: .delegate(.didUpdate(edited)))))
                await store.finish()
            }
        }

        @Test
        func aFailedBookmarkChangeShowsAnAlert() async {
            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.updateBookmark = { _, _, _ in throw EntriesFailure() }
            }

            await store.send(
                .path(.element(id: detailID, action: .delegate(.didChangeBookmark(false))))
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

            await store.send(.destination(.presented(.createEntry(.delegate(.didCreate(.blueMoon)))))) {
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
            state.path.append(EntryDetail.State(entry: SharedReader(value: .burningCandle)))
            state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
            let detailID = Array(state.path.ids)[1]

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
                    .path(.element(id: detailID, action: .delegate(.didDelete)))
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
                .path(.element(id: detailID, action: .delegate(.didDelete)))
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
            let remaining = [Entry.burningCandle, Entry.wrongTree]
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

        @Test
        func anEditedEntryUpdatesItsDetail() async throws {
            let edited = try Entry(
                createdAt: Entry.blueMoon.createdAt,
                definition: "A rare event.",
                id: Entry.blueMoon.id,
                isBookmarked: Entry.blueMoon.isBookmarked,
                term: Entry.blueMoon.term
            )
            let snapshot = Entry.mocks.map { $0.id == edited.id ? edited : $0 }

            var state = Home.State(user: .mock)
            state.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: Entry.mocks)) }
            let entry = try #require(state.filteredEntries.first { $0.wrappedValue.id == Entry.blueMoon.id })
            state.path.append(EntryDetail.State(entry: entry))
            let detailID = Array(state.path.ids)[0]

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.entriesUpdated(EntriesSnapshot(entries: snapshot, isSyncing: false))) {
                $0.$entries.withLock { $0 = .loaded(IdentifiedArray(uniqueElements: snapshot)) }
                $0.isSyncing = false
            }
            expectNoDifference(store.state.path[id: detailID]?.entry, edited)
        }

        // The settings need the user, and home is the scene that holds it
        @Test
        func theSettingsButtonOpensTheSettings() async {
            let store = TestStore(initialState: Home.State(user: .mock)) {
                Home()
            }

            await store.send(.settingsButtonTapped) {
                $0.destination = .settings(Settings.State(user: .mock))
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
            state.destination = .settings(Settings.State(user: .mock))

            let store = TestStore(initialState: state) {
                Home()
            }

            await store.send(.entrySaveFailed(Entry.blueMoon.id, EntriesFailure())) {
                $0.pendingFailures = [.entrySave]
            }
            await store.send(.entrySaveFailed(Entry.burningCandle.id, EntriesFailure()))
            await store.send(.entryDeleteFailed(Entry.wrongTree.id, EntriesFailure())) {
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
            state.destination = .settings(Settings.State(destination: .alert(.confirmAccountDeletion), user: .mock))

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
                $0.destination = .settings(Settings.State(user: .mock))
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
                    Settings.State(destination: .alert(.accountDeletionFailed(.notFullyDeleted)), user: .mock)
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
            case .entrySave: .entrySaveFailed(Entry.blueMoon.id, EntriesFailure())
            }
        }

        private struct EntriesFailure: Error {}
    }
}
