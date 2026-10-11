//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import CustomDump
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct SettingsTests {
        // A sign out clears the local entries
        @Test
        func theSignOutButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Self.state()) {
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
                let store = TestStore(initialState: Self.state(destination: .alert(.confirmSignOut))) {
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
            let store = TestStore(initialState: Self.state(destination: .alert(.confirmSignOut))) {
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
            let store = TestStore(initialState: Self.state(destination: .alert(.confirmSignOut))) {
                Settings()
            }

            await store.send(.destination(.dismiss)) {
                $0.destination = nil
            }
        }

        // The deletion removes the entries from every device
        @Test
        func theDeleteAccountButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Self.state()) {
                Settings()
            }

            await store.send(.deleteAccountButtonTapped) {
                $0.destination = .alert(.confirmAccountDeletion)
            }
        }

        @Test
        func confirmingTheAccountDeletionAsksHomeToDeleteTheAccount() async {
            let store = TestStore(initialState: Self.state(destination: .alert(.confirmAccountDeletion))) {
                Settings()
            }

            await store.send(.destination(.presented(.alert(.confirmAccountDeletion)))) {
                $0.destination = nil
            }
            await store.receive(\.delegate.didConfirmAccountDeletion)
        }

        // Home presents the settings, so only the dismiss effect can close them
        @Test
        func theDismissButtonClosesTheSettings() async {
            await confirmation("Dismisses the settings") { dismissesSettings in
                let store = TestStore(initialState: Self.state()) {
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

            let store = TestStore(initialState: Self.state()) {
                Settings()
            } withDependencies: {
                $0.entriesClient.save = { entry, uid in
                    expectNoDifference(uid, User.mock.uid)
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
                let store = TestStore(initialState: Self.state()) {
                    Settings()
                } withDependencies: {
                    $0.entriesClient.deleteAll = { uid in
                        expectNoDifference(uid, User.mock.uid)
                        deletesAllEntries()
                    }
                }

                await store.send(.debugDeleteAllEntriesButtonTapped)
                await store.finish()
            }
        }

        @Test
        func theDebugResetWelcomeToggleSetsTheFlagForTheNextLaunch() async {
            let store = TestStore(initialState: Self.state()) {
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

        private static func state(destination: Settings.Destination.State? = nil) -> Settings.State {
            Settings.State(destination: destination, entries: SharedReader(value: .loaded([])), user: .mock)
        }

        private struct SignOutFailure: Error {}
    }
}
