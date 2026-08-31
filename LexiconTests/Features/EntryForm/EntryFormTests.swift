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

    @Test
    func editingAnEntryKeepsItsIdentity() async {
        var edited = Entry.blueMoon
        edited.definition = "A rare event."

        let store = TestStore(initialState: EntryForm.State(entry: .blueMoon)) {
            EntryForm()
        }

        await store.send(.binding(.set(\.definition, "  A rare event.  "))) {
            $0.definition = "  A rare event.  "
        }
        await store.send(.saveButtonTapped)
        await store.receive(\.delegate.didSubmit, edited)
    }
}
