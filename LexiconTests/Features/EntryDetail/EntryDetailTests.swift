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
}
