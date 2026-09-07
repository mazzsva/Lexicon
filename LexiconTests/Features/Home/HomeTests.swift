//
//  HomeTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import CustomDump
import Foundation
import Testing

@testable import Lexicon

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
            $0.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
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

    // A snapshot stops the syncing only when it comes from the server without a local write
    @Test
    func anEntriesUpdateStoresThemAndStopsTheSyncing() async {
        let store = TestStore(initialState: Home.State(user: .mock)) {
            Home()
        }

        await store.send(.entriesUpdated(.mock)) {
            $0.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
            $0.isSyncing = false
        }
    }

    // Nil entries mean the first load, and an empty array means an empty list
    @Test
    func theEntriesAreEmptyWhileTheFirstLoadRuns() {
        let state = Home.State(user: .mock)

        #expect(state.isLoadingFirstEntries)
        expectNoDifference(state.filteredEntries.map(\.wrappedValue), [])
    }

    // The count ignores the search text and the bookmark filter
    @Test
    func theEntryCountFollowsTheEntries() {
        var state = Home.State(user: .mock)
        expectNoDifference(state.entryCount, 0)

        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        expectNoDifference(state.entryCount, 3)
    }

    // The entries the user can already read must not disappear on a failure
    @Test
    func aFailedStreamKeepsTheEntriesAndRetriesAfterFiveSeconds() async {
        let clock = TestClock()
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
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

    // An empty array replaces nil, so the list shows the empty state and not the spinner
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
            $0.$entries.withLock { $0 = [] }
        }

        await clock.advance(by: .seconds(5))
        await store.receive(\.entriesRetryTimerElapsed)
        await store.finish()
    }

    // The haptic welcomes the user, so it does not depend on the entries
    @Test
    func aFreshSignInPlaysItsHapticEvenWhenTheFirstLoadFails() async {
        let clock = TestClock()
        let state = Home.State(user: .mock, sessionOrigin: .freshSignIn(isNewAccount: false))

        await confirmation("Plays the success haptic") { playsHaptic in
            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.continuousClock = clock
                $0.entriesClient.entries = { _ in
                    AsyncThrowingStream { continuation in continuation.finish() }
                }
                $0.hapticsClient.success = { playsHaptic() }
            }

            await store.send(.entriesStreamFailed) {
                $0.$entries.withLock { $0 = [] }
            }
            await clock.advance(by: .seconds(5))
            await store.receive(\.entriesRetryTimerElapsed)
            await store.finish()
        }
    }

    // A sync cannot finish without a network, so the offline status wins
    @Test
    func theConnectivityDrivesTheSyncStatus() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
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
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.bookmarkFilterButtonTapped) {
            $0.isShowingBookmarkedOnly = true
        }
        expectNoDifference(store.state.filteredEntries.map(\.wrappedValue), [.blueMoon])
    }

    // The filter button disappears with the last entry, so the filter must clear itself
    @Test
    func anEmptyListClearsTheBookmarkFilter() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.isShowingBookmarkedOnly = true

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.entriesUpdated(.empty)) {
            $0.$entries.withLock { $0 = [] }
            $0.isShowingBookmarkedOnly = false
            $0.isSyncing = false
        }
    }

    // The user can remember the meaning of an entry but not its term
    @Test
    func theSearchTextMatchesTheTermsAndTheDefinitions() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }

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

    // A form without an entry creates one, and a form with an entry edits it
    @Test
    func theNewEntryButtonOpensAnEmptyForm() async {
        let store = TestStore(initialState: Home.State(user: .mock)) {
            Home()
        }

        await store.send(.newEntryButtonTapped) {
            $0.destination = .createEntry(EntryForm.State())
        }
    }

    // The form only reports the entry, and home writes it to the server
    @Test
    func creatingAnEntrySavesItAndClosesTheForm() async {
        let now = Date(timeIntervalSince1970: 1_751_000_000)
        let created = Entry(
            createdAt: now,
            definition: "The easiest wins, taken first.",
            id: UUID(0),
            isBookmarked: false,
            term: "Low-hanging fruit"
        )

        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.destination = .createEntry(EntryForm.State())

        await confirmation("Saves the entry") { savesEntry in
            await confirmation("Plays the success haptic") { playsHaptic in
                let store = TestStore(initialState: state) {
                    Home()
                } withDependencies: {
                    $0.date.now = now
                    $0.entriesClient.save = { entry, uid in
                        expectNoDifference(entry, created)
                        expectNoDifference(uid, User.mock.uid)
                        savesEntry()
                    }
                    $0.hapticsClient.success = { playsHaptic() }
                    $0.uuid = .incrementing
                }

                store.exhaustivity = .off

                await store.send(
                    .destination(.presented(.createEntry(.binding(.set(\.term, "  Low-hanging fruit  ")))))
                )
                await store.send(
                    .destination(.presented(.createEntry(.binding(.set(\.definition, created.definition)))))
                )
                await store.send(.destination(.presented(.createEntry(.saveButtonTapped))))
                await store.receive(\.destination.presented.createEntry.delegate.didSubmit) {
                    $0.destination = nil
                }
                await store.finish()
            }
        }
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

    // Home reads the delegate actions only, and the detail keeps the rest
    @Test
    func aNonDelegateDetailActionIsHandledByTheDetail() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
        let detailID = Array(state.path.ids)[0]

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.path(.element(id: detailID, action: .deleteButtonTapped))) {
            $0.path[id: detailID]?.destination = .alert(.confirmDeletion)
        }
    }

    // The detail leaves the stack first because its entry is about to disappear
    @Test
    func deletingFromTheDetailPopsBackAndDeletesTheEntry() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
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

    // The detail stays on screen because it reads the entry from the shared state
    @Test
    func updatingFromTheDetailSavesTheEntry() async {
        var bookmarked = Entry.burningCandle
        bookmarked.isBookmarked = true

        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.path.append(EntryDetail.State(entry: SharedReader(value: .burningCandle)))
        let detailID = Array(state.path.ids)[0]

        await confirmation("Saves the entry") { savesEntry in
            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.save = { entry, uid in
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

    // A different device can delete the entry while its detail is on screen
    @Test
    func aDeletedEntryPopsItsDetail() async {
        let remaining = [Entry.burningCandle, Entry.lowHangingFruit]
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
        let detailID = Array(state.path.ids)[0]

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.entriesUpdated(EntriesSnapshot(entries: remaining, isSyncing: false))) {
            $0.$entries.withLock { $0 = IdentifiedArray(uniqueElements: remaining) }
            $0.isSyncing = false
            $0.path.pop(from: detailID)
        }
    }

    // A snapshot that still holds the entry must not disturb the stack
    @Test
    func aSurvivingEntryKeepsItsDetail() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
        state.isSyncing = false

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.entriesUpdated(.mock))
    }

    // The detail pops before the delete reaches the server, so an alert must report the failure
    @Test
    func aFailedDeletionShowsAnAlert() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
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
            $0.destination = .alert(.entryDeleteFailed)
        }
    }

    // The deletion of one entry must not interrupt the creation of a different one
    @Test
    func aFailedDeletionKeepsThePresentedForm() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.destination = .createEntry(EntryForm.State())

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.entryDeleteFailed(Entry.blueMoon.id, EntriesFailure()))
    }

    // The save leaves no trace on screen, so an alert must report the failure
    @Test
    func aFailedSaveShowsAnAlert() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
        let detailID = Array(state.path.ids)[0]

        let store = TestStore(initialState: state) {
            Home()
        } withDependencies: {
            $0.entriesClient.save = { _, _ in throw EntriesFailure() }
        }

        await store.send(
            .path(.element(id: detailID, action: .delegate(.didUpdate(.blueMoon))))
        )
        await store.receive(\.entrySaveFailed) {
            $0.destination = .alert(.entrySaveFailed)
        }
    }

    // A save that fails in the background must not interrupt the form on screen
    @Test
    func aFailedSaveKeepsThePresentedForm() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.destination = .createEntry(EntryForm.State())

        let store = TestStore(initialState: state) {
            Home()
        }

        await store.send(.entrySaveFailed(Entry.blueMoon.id, EntriesFailure()))
    }

    private struct EntriesFailure: Error {}
}
