//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AuthenticationServices
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

    @Test
    func deleteAccountButtonAsksForConfirmation() async {
        let store = TestStore(initialState: Settings.State(user: .mock)) {
            Settings()
        }

        await store.send(.deleteAccountButtonTapped) {
            $0.alert = .confirmAccountDeletion
        }
    }

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

    @Test
    func aCanceledReauthorizationIsSilent() async {
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

    @Test
    func aFailureAfterTheEntriesReportsAnUnfinishedDeletion() async {
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

    @Test
    func aFailureAfterTheRevokeSignsTheUserOut() async {
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

    private struct DeletionFailure: Error {}

    private struct SignOutFailure: Error {}
}
