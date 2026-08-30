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
}
