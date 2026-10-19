//
//  AccountDeletionTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import AuthenticationServices
import ComposableArchitecture
import CustomDump
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct AccountDeletionTests {
        // The account must exist until the entries and the Apple token are gone
        @Test
        func aStartedDeletionWalksThroughEveryStep() async {
            let clock = TestClock()
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
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

            await store.send(.deletionConfirmed)
            await store.receive(\.appleCredentialReceived, .mock) {
                $0.step = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.step = .entriesDeleted
            }
            await store.receive(\.appleCredentialRevoked) {
                $0.step = .credentialRevoked
            }
            await store.receive(\.accountDeleted)
            await clock.advance(by: AccountDeletion.timeout)
            await store.finish()
        }

        // The user closed the Apple sheet, so the app returns to the settings
        @Test
        func aCanceledReauthorizationStopsTheDeletionSilently() async {
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
            } withDependencies: {
                $0.signInWithAppleClient.requestCredential = { throw ASAuthorizationError(.canceled) }
            }

            await store.send(.deletionConfirmed)
            await store.receive(\.deletionFailed)
            await store.receive(\.delegate.didCancel)
        }

        @Test
        func aCancellationErrorFromTheCredentialRequestFailsTheDeletion() async {
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
            } withDependencies: {
                $0.signInWithAppleClient.requestCredential = { throw CancellationError() }
            }

            await store.send(.deletionConfirmed)
            await store.receive(\.deletionFailed)
            await store.receive(\.delegate.didFail, .notDeleted)
        }

        // Without the code the app cannot revoke the Apple token, so it deletes nothing
        @Test
        func aCredentialWithoutAnAuthorizationCodeFailsTheDeletion() async {
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
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

            await store.send(.deletionConfirmed)
            await store.receive(\.appleCredentialReceived)
            await store.receive(\.delegate.didFail, .notDeleted)
        }

        // No entry is gone yet, so the alert must not report an unfinished deletion
        @Test
        func aFailureBeforeTheEntriesAreDeletedReportsAFailedDeletion() async {
            let clock = TestClock()
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
            } withDependencies: {
                $0.authClient.reauthenticate = { _ in }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in throw DeletionFailure() }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.deletionConfirmed)
            await store.receive(\.appleCredentialReceived) {
                $0.step = .deleting
            }
            await store.receive(\.deletionFailed)
            await store.receive(\.delegate.didFail, .notDeleted)
            await store.finish()
        }

        // The entries are already gone, so the alert must not report a deletion that did not start
        @Test
        func aFailureAfterTheEntriesAreDeletedReportsAnUnfinishedDeletion() async {
            let clock = TestClock()
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
            } withDependencies: {
                $0.authClient.reauthenticate = { _ in }
                $0.authClient.revokeAppleToken = { _ in throw DeletionFailure() }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.deletionConfirmed)
            await store.receive(\.appleCredentialReceived) {
                $0.step = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.step = .entriesDeleted
            }
            await store.receive(\.deletionFailed)
            await store.receive(\.delegate.didFail, .notFullyDeleted)
            await store.finish()
        }

        // Apple no longer trusts the app, so the session cannot continue
        @Test
        func aFailureAfterTheCredentialIsRevokedSignsTheUserOut() async {
            let clock = TestClock()
            await confirmation("Signs the user out") { signsOut in
                let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                    AccountDeletion()
                } withDependencies: {
                    $0.authClient.deleteAccount = { throw DeletionFailure() }
                    $0.authClient.reauthenticate = { _ in }
                    $0.authClient.revokeAppleToken = { _ in }
                    $0.authClient.signOut = { signsOut() }
                    $0.continuousClock = clock
                    $0.entriesClient.deleteAll = { _ in }
                    $0.signInWithAppleClient.requestCredential = { .mock }
                }

                await store.send(.deletionConfirmed)
                await store.receive(\.appleCredentialReceived) {
                    $0.step = .deleting
                }
                await store.receive(\.entriesDeleted) {
                    $0.step = .entriesDeleted
                }
                await store.receive(\.appleCredentialRevoked) {
                    $0.step = .credentialRevoked
                }
                await store.receive(\.deletionFailed)
                await store.finish()
            }
        }

        // The user keeps a session that Apple no longer trusts, so the alert must say so
        @Test
        func aFailedSignOutAfterTheRevokeFailsTheDeletion() async {
            let clock = TestClock()
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
            } withDependencies: {
                $0.authClient.deleteAccount = { throw DeletionFailure() }
                $0.authClient.reauthenticate = { _ in }
                $0.authClient.revokeAppleToken = { _ in }
                $0.authClient.signOut = { throw SignOutFailure() }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.deletionConfirmed)
            await store.receive(\.appleCredentialReceived) {
                $0.step = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.step = .entriesDeleted
            }
            await store.receive(\.appleCredentialRevoked) {
                $0.step = .credentialRevoked
            }
            await store.receive(\.deletionFailed)
            await store.receive(\.signOutFailed)
            await store.receive(\.delegate.didFail, .notSignedOut)
            await store.finish()
        }

        // A request that never returns leaves the user with a spinner
        @Test(
            arguments: [
                (.reauthenticate, .notDeleted),
                (.deleteAll, .notDeleted),
                (.revokeAppleToken, .notFullyDeleted),
            ] as [(StalledStep, AccountDeletion.Failure)]
        )
        func aStalledDeletionTimesOutAfterOneMinute(
            stalledStep: StalledStep,
            failure: AccountDeletion.Failure
        ) async {
            let clock = TestClock()
            let isStallCanceled = LockIsolated(false)
            let stall: @Sendable () async -> Void = {
                await withTaskCancellationHandler {
                    _ = await Task { try? await clock.sleep(for: .seconds(3600)) }.value
                } onCancel: {
                    isStallCanceled.setValue(true)
                }
            }
            let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                AccountDeletion()
            } withDependencies: {
                $0.continuousClock = clock
                $0.signInWithAppleClient.requestCredential = { .mock }
                switch stalledStep {
                case .reauthenticate:
                    $0.authClient.reauthenticate = { _ in await stall() }
                case .deleteAll:
                    $0.authClient.reauthenticate = { _ in }
                    $0.entriesClient.deleteAll = { _ in await stall() }
                case .revokeAppleToken:
                    $0.authClient.reauthenticate = { _ in }
                    $0.authClient.revokeAppleToken = { _ in await stall() }
                    $0.entriesClient.deleteAll = { _ in }
                }
            }

            await store.send(.deletionConfirmed)
            await store.receive(\.appleCredentialReceived) {
                $0.step = .deleting
            }
            if stalledStep == .revokeAppleToken {
                await store.receive(\.entriesDeleted) {
                    $0.step = .entriesDeleted
                }
            }
            await clock.advance(by: AccountDeletion.timeout - .milliseconds(1))
            #expect(!isStallCanceled.value)
            await clock.advance(by: .milliseconds(1))
            await store.receive(\.deletionTimerElapsed)
            await store.receive(\.delegate.didFail, failure)
            #expect(isStallCanceled.value)
            await clock.advance(by: .seconds(3600))
            await store.finish()
        }

        @Test
        func aStalledDeletionAfterTheRevokeSignsTheUserOut() async {
            let clock = TestClock()
            let isStallCanceled = LockIsolated(false)
            let stall: @Sendable () async -> Void = {
                await withTaskCancellationHandler {
                    _ = await Task { try? await clock.sleep(for: .seconds(3600)) }.value
                } onCancel: {
                    isStallCanceled.setValue(true)
                }
            }
            await confirmation("Signs the user out") { signsOut in
                let store = TestStore(initialState: AccountDeletion.State(uid: User.mock.uid)) {
                    AccountDeletion()
                } withDependencies: {
                    $0.authClient.signOut = { signsOut() }
                    $0.continuousClock = clock
                    $0.signInWithAppleClient.requestCredential = { .mock }
                    $0.authClient.deleteAccount = { await stall() }
                    $0.authClient.reauthenticate = { _ in }
                    $0.authClient.revokeAppleToken = { _ in }
                    $0.entriesClient.deleteAll = { _ in }
                }

                await store.send(.deletionConfirmed)
                await store.receive(\.appleCredentialReceived) {
                    $0.step = .deleting
                }
                await store.receive(\.entriesDeleted) {
                    $0.step = .entriesDeleted
                }
                await store.receive(\.appleCredentialRevoked) {
                    $0.step = .credentialRevoked
                }
                await clock.advance(by: AccountDeletion.timeout - .milliseconds(1))
                #expect(!isStallCanceled.value)
                await clock.advance(by: .milliseconds(1))
                await store.receive(\.deletionTimerElapsed)
                #expect(isStallCanceled.value)
                await clock.advance(by: .seconds(3600))
                await store.finish()
            }
        }

        enum StalledStep: Sendable {
            case deleteAll
            case reauthenticate
            case revokeAppleToken
        }

        private struct DeletionFailure: Error {}

        private struct SignOutFailure: Error {}
    }
}
