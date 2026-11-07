//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AccountKit
import ComposableArchitecture
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct SettingsTests {
        // A sign out clears the local data
        @Test
        func theSignOutButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.account(.signOutButtonTapped)) {
                $0.account.alert = .confirmSignOut
            }
        }

        // The deletion removes the entries from every device
        @Test
        func theDeleteAccountButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.account(.deleteAccountButtonTapped)) {
                $0.account.alert = .confirmAccountDeletion
            }
        }

        // Home presents the settings, so only the dismiss effect can close them
        @Test
        func theDismissButtonClosesTheSettings() async {
            await confirmation("Dismisses the settings") { dismissesSettings in
                let store = TestStore(initialState: Settings.State(user: .mock)) {
                    Settings()
                } withDependencies: {
                    $0.dismiss = DismissEffect { dismissesSettings() }
                }

                await store.send(.dismissButtonTapped)
                await store.finish()
            }
        }
    }
}
