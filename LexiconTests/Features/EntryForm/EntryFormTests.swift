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
}
