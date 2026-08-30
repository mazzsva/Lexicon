//
//  EntryDetailTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 30/08/26.
//

import ComposableArchitecture
import Testing

@testable import Lexicon

@MainActor
struct EntryDetailTests {
    @Test
    func deleteButtonShowsConfirmationAlert() async {
        let store = TestStore(
            initialState: EntryDetail.State(entry: SharedReader(value: .blueMoon))
        ) {
            EntryDetail()
        }

        await store.send(.deleteButtonTapped) {
            $0.destination = .alert(.confirmDeletion)
        }
    }

    @Test
    func confirmingDeletionTellsTheParent() async {
        let store = TestStore(
            initialState: EntryDetail.State(
                destination: .alert(.confirmDeletion),
                entry: SharedReader(value: .blueMoon)
            )
        ) {
            EntryDetail()
        }

        await store.send(.destination(.presented(.alert(.confirmDeletion)))) {
            $0.destination = nil
        }
        await store.receive(\.delegate.didDelete, Entry.blueMoon.id)
    }

    @Test
    func cancelingDeletionKeepsTheEntry() async {
        let store = TestStore(
            initialState: EntryDetail.State(
                destination: .alert(.confirmDeletion),
                entry: SharedReader(value: .blueMoon)
            )
        ) {
            EntryDetail()
        }

        await store.send(.destination(.dismiss)) {
            $0.destination = nil
        }
    }

    @Test
    func bookmarkButtonTellsTheParent() async {
        await confirmation("Plays the selection haptic") { playsHaptic in
            let store = TestStore(
                initialState: EntryDetail.State(entry: SharedReader(value: .burningCandle))
            ) {
                EntryDetail()
            } withDependencies: {
                $0.hapticsClient.selection = { playsHaptic() }
            }

            var bookmarked = Entry.burningCandle
            bookmarked.isBookmarked = true

            await store.send(.bookmarkButtonTapped)
            await store.receive(\.delegate.didUpdate, bookmarked)
        }
    }

    @Test
    func editButtonOpensTheFormOnTheEntry() async {
        let store = TestStore(
            initialState: EntryDetail.State(entry: SharedReader(value: .blueMoon))
        ) {
            EntryDetail()
        }

        await store.send(.editButtonTapped) {
            $0.destination = .editEntry(EntryForm.State(entry: .blueMoon))
        }
    }

    @Test
    func savingTheEditedEntryClosesTheFormAndTellsTheParent() async {
        await confirmation("Plays the success haptic") { playsHaptic in
            let store = TestStore(
                initialState: EntryDetail.State(
                    destination: .editEntry(EntryForm.State(entry: .blueMoon)),
                    entry: SharedReader(value: .blueMoon)
                )
            ) {
                EntryDetail()
            } withDependencies: {
                $0.hapticsClient.success = { playsHaptic() }
            }

            var edited = Entry.blueMoon
            edited.definition = "Something that almost never happens."

            await store.send(
                .destination(.presented(.editEntry(.binding(.set(\.definition, edited.definition)))))
            ) { state in
                state.destination?.modify(\.editEntry) { $0.definition = edited.definition }
            }
            await store.send(.destination(.presented(.editEntry(.saveButtonTapped))))
            await store.receive(\.destination.presented.editEntry.delegate.didSubmit, edited) {
                $0.destination = nil
            }
            await store.receive(\.delegate.didUpdate, edited)
        }
    }
}
