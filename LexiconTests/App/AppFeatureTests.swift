//
//  AppFeatureTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 01/09/26.
//

import ComposableArchitecture
import DependenciesTestSupport
import Testing

@testable import Lexicon

@MainActor
struct AppFeatureTests {
    @Test(.dependencies)
    func theWelcomeIsPresentedOnlyOnceTheAppIsReady() {
        var state = AppFeature.State()
        #expect(!state.isPresentingWelcome)

        state.scene = .signIn(SignIn.State())
        #expect(state.isPresentingWelcome)

        state.$hasDismissedWelcome.withLock { $0 = true }
        #expect(!state.isPresentingWelcome)
    }
}
