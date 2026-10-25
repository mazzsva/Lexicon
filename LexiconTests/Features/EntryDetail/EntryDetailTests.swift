//
//  EntryDetailTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 30/08/26.
//

import ComposableArchitecture
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct EntryDetailTests {
        // The detail reads the entry, and only home can write it
        @Test
        func theBookmarkButtonBookmarksTheEntryAndTellsTheParent() async {
            await confirmation("Plays the selection haptic") { playsHaptic in
                let store = TestStore(
                    initialState: EntryDetail.State(entry: SharedReader(value: .blueMoon))
                ) {
                    EntryDetail()
                } withDependencies: {
                    $0.hapticsClient.selection = { playsHaptic() }
                }

                await store.send(.bookmarkButtonTapped)
                await store.receive(\.delegate.didChangeBookmark, true)
                await store.finish()
            }
        }

        // Blue moon starts with a bookmark, so the same button removes it
        @Test
        func theBookmarkButtonRemovesTheBookmarkAndTellsTheParent() async {
            await confirmation("Plays the selection haptic") { playsHaptic in
                let store = TestStore(
                    initialState: EntryDetail.State(entry: SharedReader(value: .burningCandle))
                ) {
                    EntryDetail()
                } withDependencies: {
                    $0.hapticsClient.selection = { playsHaptic() }
                }

                await store.send(.bookmarkButtonTapped)
                await store.receive(\.delegate.didChangeBookmark, false)
                await store.finish()
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

        // The detail closes the form itself, and home receives the content to save
        @Test
        func savingTheEditedEntryClosesTheFormAndTellsTheParent() async throws {
            let edited = try Entry(
                createdAt: Entry.blueMoon.createdAt,
                definition: "Something that almost never happens.",
                id: Entry.blueMoon.id,
                isBookmarked: Entry.blueMoon.isBookmarked,
                term: Entry.blueMoon.term
            )

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

                await store.send(
                    .destination(.presented(.editEntry(.binding(.set(\.definition, edited.definition)))))
                ) {
                    $0.destination?.modify(\.editEntry) { $0.definition = edited.definition }
                }
                await store.send(.destination(.presented(.editEntry(.saveButtonTapped))))
                await store.receive(\.destination.presented.editEntry.delegate.didUpdate, edited.content) {
                    $0.destination = nil
                }
                await store.receive(\.delegate.didUpdate, edited.content)
                await store.finish()
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
            await store.receive(\.delegate.didDelete)
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
}
