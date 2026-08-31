//
//  SignInTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AuthenticationServices
import ComposableArchitecture
import Testing

@testable import Lexicon

@MainActor
struct SignInTests {
    @Test
    func signingInAuthorizesTheCredentialAndSignsIn() async {
        await confirmation("Signs in with the credential") { signsIn in
            let store = TestStore(initialState: SignIn.State()) {
                SignIn()
            } withDependencies: {
                $0.authClient.signIn = { credential in
                    #expect(credential == .mock)
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

    private struct SignInFailure: Error {}
}
