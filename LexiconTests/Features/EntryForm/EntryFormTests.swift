//
//  EntryFormTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct EntryFormTests {
        // An entry needs a term, and the definition can stay empty
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

        // The form gives the entry an identity, so the save does not wait for the server
        @Test
        func creatingAnEntryGeneratesItsIdentityAndDate() async throws {
            let now = Date(timeIntervalSince1970: 1_751_000_000)
            let created = try Entry(
                createdAt: now,
                definition: "The easiest wins, taken first.",
                id: UUID(0),
                isBookmarked: false,
                term: "Low-hanging fruit"
            )

            let store = TestStore(initialState: EntryForm.State()) {
                EntryForm()
            } withDependencies: {
                $0.date.now = now
                $0.uuid = .incrementing
            }

            await store.send(.binding(.set(\.term, "  Low-hanging fruit  "))) {
                $0.term = "  Low-hanging fruit  "
            }
            await store.send(.binding(.set(\.definition, created.definition))) {
                $0.definition = created.definition
            }
            await store.send(.saveButtonTapped)
            await store.receive(\.delegate.didCreate, created)
        }

        // The identity and the date come from the original, so the save replaces it
        @Test
        func editingAnEntryKeepsItsIdentity() async throws {
            let edited = try Entry(
                createdAt: Entry.blueMoon.createdAt,
                definition: "A rare event.",
                id: Entry.blueMoon.id,
                isBookmarked: Entry.blueMoon.isBookmarked,
                term: Entry.blueMoon.term
            )

            let store = TestStore(initialState: EntryForm.State(entry: .blueMoon)) {
                EntryForm()
            }

            await store.send(.binding(.set(\.definition, "  A rare event.  "))) {
                $0.definition = "  A rare event.  "
            }
            await store.send(.saveButtonTapped)
            await store.receive(\.delegate.didUpdate, edited)
        }

        // The view disables the save button, and the reducer refuses the term as well
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
        func savingAnEntryOverTheSizeLimitDoesNothing() async {
            let term = String(repeating: "a", count: Entry.Content.maximumSize / 2)
            let definition = String(repeating: "é", count: Entry.Content.maximumSize / 4 + 1)

            let store = TestStore(initialState: EntryForm.State()) {
                EntryForm()
            }

            await store.send(.binding(.set(\.term, term))) {
                $0.term = term
            }
            await store.send(.binding(.set(\.definition, definition))) {
                $0.definition = definition
            }
            #expect(!store.state.isSubmittable)

            await store.send(.saveButtonTapped)
        }

        // The parent presents the form, so only the dismiss effect can close it
        @Test
        func theDismissButtonClosesTheForm() async {
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
}
