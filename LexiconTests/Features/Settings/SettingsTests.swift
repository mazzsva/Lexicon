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

            await store.send(.signOutButtonTapped) {
                $0.destination = .alert(.confirmSignOut)
            }
        }

        // The app feature listens to Firebase, so the settings only start the sign out
        @Test
        func confirmingTheSignOutSignsTheUserOut() async {
            await confirmation("Signs the user out") { signsOut in
                let store = TestStore(initialState: Settings.State(destination: .alert(.confirmSignOut), user: .mock)) {
                    Settings()
                } withDependencies: {
                    $0.authClient.signOut = { signsOut() }
                }

                await store.send(.destination(.presented(.alert(.confirmSignOut)))) {
                    $0.destination = nil
                }
                await store.finish()
            }
        }

        // The settings stay on screen because the user is still signed in
        @Test
        func aFailedSignOutShowsAnAlert() async {
            let store = TestStore(initialState: Settings.State(destination: .alert(.confirmSignOut), user: .mock)) {
                Settings()
            } withDependencies: {
                $0.authClient.signOut = { throw SignOutFailure() }
            }

            await store.send(.destination(.presented(.alert(.confirmSignOut)))) {
                $0.destination = nil
            }
            await store.receive(\.signOutFailed) {
                $0.destination = .alert(.signOutFailed)
            }
        }

        // A dismissed confirmation must not sign the user out
        @Test
        func dismissingTheAlertClearsIt() async {
            let store = TestStore(initialState: Settings.State(destination: .alert(.confirmSignOut), user: .mock)) {
                Settings()
            }

            await store.send(.destination(.dismiss)) {
                $0.destination = nil
            }
        }

        // The deletion removes the entries from every device
        @Test
        func theDeleteAccountButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.deleteAccountButtonTapped) {
                $0.destination = .alert(.confirmAccountDeletion)
            }
        }

        @Test
        func confirmingTheAccountDeletionAsksHomeToDeleteTheAccount() async {
            let store = TestStore(
                initialState: Settings.State(destination: .alert(.confirmAccountDeletion), user: .mock)
            ) {
                Settings()
            }

            await store.send(.destination(.presented(.alert(.confirmAccountDeletion)))) {
                $0.destination = nil
            }
            await store.receive(\.delegate.didConfirmAccountDeletion)
        }

        // Every failure needs its own message, because the user decides what to do next from it
        @Test(
            arguments: [
                (
                    AccountDeletion.Failure.connectionFailed,
                    TextState("Your account couldn't be deleted. Check your connection and try again.")
                ),
                (.notDeleted, TextState("Your account couldn't be deleted.")),
                (.notFullyDeleted, TextState("Your account couldn't be fully deleted.")),
                (.notSignedOut, TextState("You couldn't be signed out.")),
            ] as [(AccountDeletion.Failure, TextState)]
        )
        func anAccountDeletionFailureHasItsOwnMessage(failure: AccountDeletion.Failure, message: TextState) {
            expectNoDifference(AlertState<Settings.Alert>.accountDeletionFailed(failure).message, message)
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

        private struct SignOutFailure: Error {}
    }
}
