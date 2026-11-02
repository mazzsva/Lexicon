//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AccountKit
import ComposableArchitecture
import CustomDump
import Foundation
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

        #if DEBUG
        // The button fills an empty account in the debug builds
        @Test
        func theDebugAddMockEntriesButtonSavesTheMockEntries() async {
            let saved = LockIsolated<[Entry]>([])

            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            } withDependencies: {
                $0.entriesClient.create = { entry, uid in
                    expectNoDifference(uid, AccountUser.mock.uid)
                    saved.withValue { $0.append(entry) }
                }
            }

            await store.send(.debugAddMockEntriesButtonTapped)
            await store.finish()
            expectNoDifference(saved.value, Entry.mocks)
        }

        // The button clears the entries and keeps the account
        @Test
        func theDebugDeleteAllEntriesButtonDeletesEveryEntry() async {
            await confirmation("Deletes all the entries") { deletesAllEntries in
                let store = TestStore(initialState: Settings.State(user: .mock)) {
                    Settings()
                } withDependencies: {
                    $0.entriesClient.deleteAll = { uid in
                        expectNoDifference(uid, AccountUser.mock.uid)
                        deletesAllEntries()
                    }
                }

                await store.send(.debugDeleteAllEntriesButtonTapped)
                await store.finish()
            }
        }

        @Test
        func theDebugResetWelcomeToggleSetsTheFlagForTheNextLaunch() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.debugResetWelcomeToggleChanged(true)) {
                $0.$showsWelcomeAtNextLaunch.withLock { $0 = true }
            }
            await store.send(.debugResetWelcomeToggleChanged(false)) {
                $0.$showsWelcomeAtNextLaunch.withLock { $0 = false }
            }
        }
        #endif
    }
}
