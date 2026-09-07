//
//  SignInTests.swift
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
struct SignInTests {
    // Apple authorizes the user first, and Firebase accepts the credential after
    @Test
    func theSignInButtonAuthorizesTheCredentialAndSignsIn() async {
        await confirmation("Signs in with the credential") { signsIn in
            let store = TestStore(initialState: SignIn.State()) {
                SignIn()
            } withDependencies: {
                $0.authClient.signIn = { credential in
                    expectNoDifference(credential, .mock)
                    signsIn()
                }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.signInButtonTapped) {
                $0.step = .awaitingAuthorization
            }
            await store.receive(\.authorizationResponse.success, .mock) {
                $0.step = .signingIn(isNewAccount: false)
            }
            await store.finish()
        }
    }

    // A second request would open a second Apple sheet
    @Test
    func theSignInButtonIsIgnoredWhileAuthenticating() async {
        var state = SignIn.State()
        state.step = .awaitingAuthorization

        let store = TestStore(initialState: state) {
            SignIn()
        }

        await store.send(.signInButtonTapped)
    }

    // The user closed the Apple sheet, so the app returns to the button
    @Test
    func aCanceledAuthorizationIsSilent() async {
        var state = SignIn.State()
        state.step = .awaitingAuthorization

        let store = TestStore(initialState: state) {
            SignIn()
        }

        await store.send(.authorizationResponse(.failure(ASAuthorizationError(.canceled)))) {
            $0.step = nil
        }
    }

    // Apple can fail before Firebase ever sees the credential
    @Test
    func aFailedAuthorizationShowsAnAlert() async {
        var state = SignIn.State()
        state.step = .awaitingAuthorization

        let store = TestStore(initialState: state) {
            SignIn()
        }

        await store.send(.authorizationResponse(.failure(SignInFailure()))) {
            $0.alert = .signInFailed
            $0.step = nil
        }
    }

    // Firebase can reject a credential that Apple authorized
    @Test
    func aFailedSignInShowsAnAlert() async {
        let store = TestStore(initialState: SignIn.State()) {
            SignIn()
        } withDependencies: {
            $0.authClient.signIn = { _ in throw SignInFailure() }
            $0.signInWithAppleClient.requestCredential = { .mock }
        }

        await store.send(.signInButtonTapped) {
            $0.step = .awaitingAuthorization
        }
        await store.receive(\.authorizationResponse.success, .mock) {
            $0.step = .signingIn(isNewAccount: false)
        }
        await store.receive(\.signInFailed) {
            $0.alert = .signInFailed
            $0.step = nil
        }
    }

    // The user can tap the sign in button again after the alert
    @Test
    func dismissingTheAlertClearsIt() async {
        var state = SignIn.State()
        state.alert = .signInFailed

        let store = TestStore(initialState: state) {
            SignIn()
        }

        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }
    }

    private struct SignInFailure: Error {}
}
