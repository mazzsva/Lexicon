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
    // The detail reads the entry, and only home can write it
    @Test
    func theBookmarkButtonBookmarksTheEntryAndTellsTheParent() async {
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

    // The form starts from the entry, so it edits and does not create
    @Test
    func theEditButtonOpensTheFormOnTheEntry() async {
        let store = TestStore(
            initialState: EntryDetail.State(entry: SharedReader(value: .blueMoon))
        ) {
            EntryDetail()
        }

        await store.send(.editButtonTapped) {
            $0.destination = .editEntry(EntryForm.State(entry: .blueMoon))
        }
    }

    // The detail closes the form itself, and home receives the entry to save
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
            store.exhaustivity = .off

            var edited = Entry.blueMoon
            edited.definition = "Something that almost never happens."

            await store.send(
                .destination(.presented(.editEntry(.binding(.set(\.definition, edited.definition)))))
            )
            await store.send(.destination(.presented(.editEntry(.saveButtonTapped))))
            await store.receive(\.delegate.didUpdate, edited) {
                $0.destination = nil
            }
        }
    }

    // The entry disappears from every device
    @Test
    func theDeleteButtonAsksForConfirmation() async {
        let store = TestStore(
            initialState: EntryDetail.State(entry: SharedReader(value: .blueMoon))
        ) {
            EntryDetail()
        }

        await store.send(.deleteButtonTapped) {
            $0.destination = .alert(.confirmDeletion)
        }
    }

    // The detail cannot delete because home holds the entries
    @Test
    func confirmingTheDeletionTellsTheParent() async {
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

    // A dismissed alert must not reach the parent
    @Test
    func cancelingTheDeletionKeepsTheEntry() async {
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
}
