//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AuthenticationServices
import ComposableArchitecture
import CustomDump
import Testing

@testable import Lexicon

@MainActor
struct SettingsTests {
    // A sign out clears the local entries
    @Test
    func theSignOutButtonAsksForConfirmation() async {
        let store = TestStore(initialState: Settings.State(user: .mock)) {
            Settings()
        }

        await store.send(.signOutButtonTapped) {
            $0.alert = .confirmSignOut
        }
    }

    // The app feature listens to Firebase, so the settings only start the sign out
    @Test
    func confirmingTheSignOutSignsTheUserOut() async {
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

    // The settings stay on screen because the user is still signed in
    @Test
    func aFailedSignOutShowsAnAlert() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmSignOut

        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.authClient.signOut = { throw SignOutFailure() }
        }

        await store.send(.alert(.presented(.confirmSignOut))) {
            $0.alert = nil
        }
        await store.receive(\.signOutFailed) {
            $0.alert = .signOutFailed
        }
    }

    // The deletion removes the entries from every device
    @Test
    func theDeleteAccountButtonAsksForConfirmation() async {
        let store = TestStore(initialState: Settings.State(user: .mock)) {
            Settings()
        }

        await store.send(.deleteAccountButtonTapped) {
            $0.alert = .confirmAccountDeletion
        }
    }

    // The account must exist until the entries and the Apple token are gone
    @Test
    func confirmingTheAccountDeletionWalksThroughEveryStep() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.authClient.deleteAccount = {}
            $0.authClient.reauthenticate = { credential in
                expectNoDifference(credential, .mock)
            }
            $0.authClient.revokeAppleToken = { authorizationCode in
                expectNoDifference(authorizationCode, AppleCredential.mock.authorizationCode)
            }
            $0.continuousClock = clock
            $0.entriesClient.deleteAll = { uid in
                expectNoDifference(uid, User.mock.uid)
            }
            $0.signInWithAppleClient.requestCredential = { .mock }
        }

        await store.send(.alert(.presented(.confirmAccountDeletion))) {
            $0.alert = nil
            $0.deletionStep = .reauthenticating
        }
        await store.receive(\.appleCredentialReceived) {
            $0.deletionStep = .deleting
        }
        await store.receive(\.entriesDeleted) {
            $0.deletionStep = .entriesDeleted
        }
        await store.receive(\.appleCredentialRevoked) {
            $0.deletionStep = .credentialRevoked
        }
        await store.finish()
    }

    // The deletion must not stop halfway
    @Test
    func theButtonsAreIgnoredWhileTheAccountIsBeingDeleted() async {
        var state = Settings.State(user: .mock)
        state.deletionStep = .deleting

        let store = TestStore(initialState: state) {
            Settings()
        }

        await store.send(.deleteAccountButtonTapped)
        await store.send(.dismissButtonTapped)
        await store.send(.signOutButtonTapped)
    }

    // The user closed the Apple sheet, so the app returns to the settings
    @Test
    func aCanceledReauthorizationStopsTheDeletionSilently() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.signInWithAppleClient.requestCredential = { throw ASAuthorizationError(.canceled) }
        }

        await store.send(.alert(.presented(.confirmAccountDeletion))) {
            $0.alert = nil
            $0.deletionStep = .reauthenticating
        }
        await store.receive(\.accountDeletionFailed) {
            $0.deletionStep = nil
        }
    }

    // Without the code the app cannot revoke the Apple token, so it deletes nothing
    @Test
    func aCredentialWithoutAnAuthorizationCodeFailsTheDeletion() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.signInWithAppleClient.requestCredential = {
                AppleCredential(
                    authorizationCode: nil,
                    idToken: "mock-id-token",
                    isFirstAuthorization: false,
                    rawNonce: "mock-raw-nonce"
                )
            }
        }

        await store.send(.alert(.presented(.confirmAccountDeletion))) {
            $0.alert = nil
            $0.deletionStep = .reauthenticating
        }
        await store.receive(\.accountDeletionFailed) {
            $0.alert = .accountDeletionFailed
            $0.deletionStep = nil
        }
    }

    // No entry is gone yet, so the alert must not report an unfinished deletion
    @Test
    func aFailureBeforeTheEntriesAreDeletedReportsAFailedDeletion() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.authClient.reauthenticate = { _ in }
            $0.continuousClock = clock
            $0.entriesClient.deleteAll = { _ in throw DeletionFailure() }
            $0.signInWithAppleClient.requestCredential = { .mock }
        }

        await store.send(.alert(.presented(.confirmAccountDeletion))) {
            $0.alert = nil
            $0.deletionStep = .reauthenticating
        }
        await store.receive(\.appleCredentialReceived) {
            $0.deletionStep = .deleting
        }
        await store.receive(\.accountDeletionFailed) {
            $0.alert = .accountDeletionFailed
            $0.deletionStep = nil
        }
        await store.finish()
    }

    // The entries are already gone, so the alert must not report a deletion that did not start
    @Test
    func aFailureAfterTheEntriesAreDeletedReportsAnUnfinishedDeletion() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.authClient.reauthenticate = { _ in }
            $0.authClient.revokeAppleToken = { _ in throw DeletionFailure() }
            $0.continuousClock = clock
            $0.entriesClient.deleteAll = { _ in }
            $0.signInWithAppleClient.requestCredential = { .mock }
        }

        await store.send(.alert(.presented(.confirmAccountDeletion))) {
            $0.alert = nil
            $0.deletionStep = .reauthenticating
        }
        await store.receive(\.appleCredentialReceived) {
            $0.deletionStep = .deleting
        }
        await store.receive(\.entriesDeleted) {
            $0.deletionStep = .entriesDeleted
        }
        await store.receive(\.accountDeletionFailed) {
            $0.alert = .accountDeletionUnfinished
            $0.deletionStep = nil
        }
        await store.finish()
    }

    // Apple no longer trusts the app, so the session cannot continue
    @Test
    func aFailureAfterTheCredentialIsRevokedSignsTheUserOut() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let clock = TestClock()
        await confirmation("Signs the user out") { signsOut in
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.deleteAccount = { throw DeletionFailure() }
                $0.authClient.reauthenticate = { _ in }
                $0.authClient.revokeAppleToken = { _ in }
                $0.authClient.signOut = { signsOut() }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.deletionStep = .entriesDeleted
            }
            await store.receive(\.appleCredentialRevoked) {
                $0.deletionStep = .credentialRevoked
            }
            await store.receive(\.accountDeletionFailed)
            await store.finish()
        }
    }

    // A request that never returns leaves the user with a spinner
    @Test
    func aStalledDeletionTimesOutAfterOneMinute() async {
        var state = Settings.State(user: .mock)
        state.alert = .confirmAccountDeletion

        let clock = TestClock()
        let store = TestStore(initialState: state) {
            Settings()
        } withDependencies: {
            $0.authClient.reauthenticate = { _ in try await Task.never() }
            $0.continuousClock = clock
            $0.signInWithAppleClient.requestCredential = { .mock }
        }

        await store.send(.alert(.presented(.confirmAccountDeletion))) {
            $0.alert = nil
            $0.deletionStep = .reauthenticating
        }
        await store.receive(\.appleCredentialReceived) {
            $0.deletionStep = .deleting
        }

        await clock.advance(by: .seconds(60))
        await store.receive(\.accountDeletionFailed) {
            $0.alert = .accountDeletionFailed
            $0.deletionStep = nil
        }
        await store.finish()
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
            let store = TestStore(initialState: Settings.State(user: .mock)) {
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
    #endif

    private struct DeletionFailure: Error {}

    private struct SignOutFailure: Error {}
}
