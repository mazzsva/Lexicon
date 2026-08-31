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

    @Test
    func confirmingSignOutSignsTheUserOut() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmSignOut

        await confirmation("Signs the user out") { signsOut in
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.signOut = { signsOut() }
            }

            await store.send(.alert(.presented(.confirmSignOut))) {
                $0.alert = nil
            }
            await store.finish()
        }
    }

    private struct SignOutFailure: Error {}
}
