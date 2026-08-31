//
//  EntryFormTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import Testing

@testable import Lexicon

@MainActor
struct EntryFormTests {
    @Test
    func onlyANonBlankTermIsSubmittable() {
        var state = EntryForm.State()
        #expect(state.isCreating)
        #expect(!state.isSubmittable)

        state.term = "   \n  "
        #expect(!state.isSubmittable)

        state.term = "Burn the candle at both ends"
        #expect(state.isSubmittable)
    }

    @Test
    func savingABlankTermDoesNothing() async {
        let store = TestStore(initialState: EntryForm.State()) {
            EntryForm()
        }

        await store.send(.binding(.set(\.term, "   "))) {
            $0.term = "   "
        }
        await store.send(.saveButtonTapped)
    }

    @Test
    func theDismissButtonDismissesTheForm() async {
        await confirmation("Dismisses the form") { dismissesForm in
            let store = TestStore(initialState: EntryForm.State(entry: .blueMoon)) {
                EntryForm()
            } withDependencies: {
                $0.dismiss = DismissEffect { dismissesForm() }
            }

            await store.send(.dismissButtonTapped)
            await store.finish()
        }
    }
}
