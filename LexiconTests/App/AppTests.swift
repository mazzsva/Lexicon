//
//  AppTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 01/09/26.
//

import AccountKit
import ComposableArchitecture
import CustomDump
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct AppTests {
        // Firestore keeps its cache on disk, so the app removes the entries of the last user
        @Test
        func aSignedOutUserAtLaunchRoutesToSignInAndClearsTheLocalData() async {
            await confirmation("Clears the local data") { clearsLocalData in
                let store = TestStore(initialState: AccountSession<Home>.State()) {
                    AccountSession<Home>()
                } withDependencies: {
                    $0.entriesClient.clearLocalData = { clearsLocalData() }
                }

                await store.send(.authUserChanged(nil)) {
                    $0.scene = .signIn(SignIn.State())
                }
                await store.finish()
            }
        }

        // The message follows the step in progress, and a system sheet gets none
        @Test
        func theLoadingMessageDescribesWhatTheAppIsDoing() {
            var state = AccountSession<Home>.State()
            #expect(state.isLoading)
            expectNoDifference(state.loadingReason.map(AppView.loadingMessage), nil)

            var signIn = SignIn.State()
            signIn.step = .signingIn
            state.scene = .signIn(signIn)
            #expect(state.isLoading)
            expectNoDifference(state.loadingReason.map(AppView.loadingMessage), "Signing in…")

            var home = Home.State(user: .mock)
            home.destination = .accountDeletion(
                AccountDeletion.State(step: .reauthenticating, uid: AccountUser.mock.uid))
            state.scene = .home(home)
            #expect(state.isLoading)
            expectNoDifference(state.loadingReason.map(AppView.loadingMessage), nil)

            state.scene?.modify(\.home) { $0.destination?.modify(\.accountDeletion) { $0.step = .deleting } }
            expectNoDifference(state.loadingReason.map(AppView.loadingMessage), "Deleting your account…")

            state.scene = .home(
                Home.State(user: .mock, sessionOrigin: .freshSignIn)
            )
            #expect(state.isLoading)
            expectNoDifference(state.loadingReason.map(AppView.loadingMessage), "Signing in…")

            signIn.step = .awaitingAuthorization
            state.scene = .signIn(signIn)
            #expect(state.isLoading)
            expectNoDifference(state.loadingReason.map(AppView.loadingMessage), nil)
        }

        // The Apple sheet covers the app, so the message waits for the deletion to start
        @Test
        func theLoadingMessageAppearsOnceTheAccountDeletionStarts() async {
            var state = AccountSession<Home>.State()
            state.scene = .home(Home.State(user: .mock))

            let store = TestStore(initialState: state) {
                AccountSession<Home>()
            } withDependencies: {
                $0.authClient.appleUserID = { nil }
                $0.authClient.reauthenticate = { _ in try await Task.never() }
                $0.continuousClock = TestClock()
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(\.scene.home.settingsButtonTapped) {
                $0.scene?
                    .modify(\.home) { home in
                        home.destination = .settings(Settings.State(user: .mock))
                    }
            }
            await store.send(\.scene.home.destination.settings.account.deleteAccountButtonTapped) {
                $0.scene?
                    .modify(\.home) { home in
                        home.destination?.modify(\.settings) { $0.account.alert = .confirmAccountDeletion }
                    }
            }
            await store.send(
                .scene(
                    .home(
                        .destination(.presented(.settings(.account(.alert(.presented(.confirmAccountDeletion))))))
                    )
                )
            ) {
                $0.scene?
                    .modify(\.home) { home in
                        home.destination?.modify(\.settings) { $0.account.alert = nil }
                    }
            }
            await store.receive(\.scene.home.destination.presented.settings.account.delegate.didConfirmAccountDeletion)
            {
                $0.scene?
                    .modify(\.home) {
                        $0.destination = .accountDeletion(AccountDeletion.State(uid: AccountUser.mock.uid))
                    }
            }
            await store.receive(\.scene.home.destination.presented.accountDeletion.deletionConfirmed)
            expectNoDifference(store.state.loadingReason.map(AppView.loadingMessage), nil)

            await store.receive(\.scene.home.destination.presented.accountDeletion.appleCredentialReceived) {
                $0.scene?
                    .modify(\.home) { home in
                        home.destination?.modify(\.accountDeletion) { $0.step = .deleting }
                    }
            }
            expectNoDifference(store.state.loadingReason.map(AppView.loadingMessage), "Deleting your account…")
            await store.send(\.scene.home.destination.dismiss) {
                $0.scene?.modify(\.home) { $0.destination = nil }
            }
        }
    }
}
