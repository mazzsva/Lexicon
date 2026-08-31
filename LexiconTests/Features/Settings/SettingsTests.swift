//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import Testing

@testable import Lexicon

@MainActor
struct SettingsTests {
    @Test
    func signOutButtonAsksForConfirmation() async {
        let store = TestStore(initialState: Settings.State(user: .mock)) {
            Settings()
        }

        await store.send(.signOutButtonTapped) {
            $0.alert = .confirmSignOut
        }
    }

    private struct SignOutFailure: Error {}
}
