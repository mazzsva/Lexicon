//
//  HomeTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import Foundation
import Testing

@testable import Lexicon

@MainActor
struct HomeTests {
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
                    #expect(id == Entry.blueMoon.id)
                    #expect(uid == User.mock.uid)
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

    @Test
    func entriesUpdatedStoresTheEntriesAndStopsSyncing() async {
        let store = TestStore(initialState: Home.State(user: .mock)) {
            Home()
        }

        await store.send(.entriesUpdated(.mock)) {
            $0.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
            $0.isSyncing = false
        }
    }

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
                    #expect(entry == bookmarked)
                    #expect(uid == User.mock.uid)
                    savesEntry()
                }
            }

            await store.send(
                .path(.element(id: detailID, action: .delegate(.didUpdate(bookmarked))))
            )
            await store.finish()
        }
    }

    @Test
    func newEntryButtonOpensAnEmptyForm() async {
        let store = TestStore(initialState: Home.State(user: .mock)) {
            Home()
        }

        await store.send(.newEntryButtonTapped) {
            $0.destination = .createEntry(EntryForm.State())
        }
    }

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
                        #expect(entry == created)
                        #expect(uid == User.mock.uid)
                        savesEntry()
                    }
                    $0.hapticsClient.success = { playsHaptic() }
                    $0.uuid = .incrementing
                }

                await store.send(
                    .destination(.presented(.createEntry(.binding(.set(\.term, "  Low-hanging fruit  ")))))
                ) { state in
                    state.destination?.modify(\.createEntry) { $0.term = "  Low-hanging fruit  " }
                }
                await store.send(
                    .destination(.presented(.createEntry(.binding(.set(\.definition, created.definition)))))
                ) { state in
                    state.destination?.modify(\.createEntry) { $0.definition = created.definition }
                }
                await store.send(.destination(.presented(.createEntry(.saveButtonTapped))))
                await store.receive(\.destination.presented.createEntry.delegate.didSubmit, created) {
                    $0.destination = nil
                }
                await store.finish()
            }
        }
    }
}
