//
//  AppFeatureTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 01/09/26.
//

import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Testing

@testable import Lexicon

@Suite(.dependencies)
@MainActor
struct AppFeatureTests {
    @Test
    func theWelcomeIsPresentedOnlyOnceTheAppIsReady() {
        var state = AppFeature.State()
        #expect(!state.isPresentingWelcome)

        state.scene = .signIn(SignIn.State())
        #expect(state.isPresentingWelcome)

        state.$hasDismissedWelcome.withLock { $0 = true }
        #expect(!state.isPresentingWelcome)
    }

    @Test
    func theWelcomeContinueButtonDismissesItForGood() async {
        var state = AppFeature.State()
        state.scene = .signIn(SignIn.State())

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.welcomeContinueButtonTapped) {
            $0.$hasDismissedWelcome.withLock { $0 = true }
        }
        #expect(!store.state.isPresentingWelcome)
    }
}
