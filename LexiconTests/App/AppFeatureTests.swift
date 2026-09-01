//
//  AppFeatureTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 01/09/26.
//

import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Testing

@testable import Lexicon

@Suite(.dependencies)
@MainActor
struct AppFeatureTests {
    @Test
    func theWelcomeIsPresentedOnlyOnceTheAppIsReady() {
        var state = AppFeature.State()
        #expect(!state.isPresentingWelcome)

        state.scene = .signIn(SignIn.State())
        #expect(state.isPresentingWelcome)

        state.$hasDismissedWelcome.withLock { $0 = true }
        #expect(!state.isPresentingWelcome)
    }

    @Test
    func theWelcomeContinueButtonDismissesItForGood() async {
        var state = AppFeature.State()
        state.scene = .signIn(SignIn.State())

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.welcomeContinueButtonTapped) {
            $0.$hasDismissedWelcome.withLock { $0 = true }
        }
        #expect(!store.state.isPresentingWelcome)
    }

    @Test
    func aSignedInUserRoutesToHomeAndVerifiesTheCredential() async {
        await confirmation("Verifies the Apple credential") { verifiesCredential in
            let store = TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.authClient.appleUserID = { "apple-user" }
                $0.signInWithAppleClient.credentialState = { userID in
                    expectNoDifference(userID, "apple-user")
                    verifiesCredential()
                    return .authorized
                }
            }

            await store.send(.authUserChanged(.mock)) {
                $0.scene = .home(Home.State(user: .mock))
            }
            await store.finish()
        }
    }

    @Test
    func aSignedOutUserRoutesToSignInAndClearsTheLocalData() async {
        await confirmation("Clears the local data") { clearsLocalData in
            let store = TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.entriesClient.clearLocalData = { clearsLocalData() }
            }

            await store.send(.authUserChanged(nil)) {
                $0.scene = .signIn(SignIn.State())
            }
            await store.finish()
        }
    }

    @Test
    func finishingTheSignInRoutesToHomeAsAFreshSession() async {
        var signIn = SignIn.State()
        signIn.step = .signingIn(isNewAccount: true)
        var state = AppFeature.State()
        state.scene = .signIn(signIn)

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.authUserChanged(.mock)) {
            $0.scene = .home(
                Home.State(user: .mock, sessionOrigin: .freshSignIn(isNewAccount: true))
            )
        }
        await store.finish()
    }

    @Test
    func theSameUserIsIgnored() async {
        var state = AppFeature.State()
        state.scene = .home(Home.State(user: .mock))

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.authUserChanged(.mock))
    }

    @Test
    func signingOutSettlesBeforeTheSignInAppears() async {
        var state = AppFeature.State()
        state.scene = .home(Home.State(user: .mock))

        let clock = TestClock()
        await confirmation("Clears the local data") { clearsLocalData in
            let store = TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.continuousClock = clock
                $0.entriesClient.clearLocalData = { clearsLocalData() }
            }

            await store.send(.authUserChanged(nil)) {
                $0.isSignedOutSettling = true
                $0.scene = .signIn(SignIn.State())
            }
            expectNoDifference(store.state.isLoading, true)

            await clock.advance(by: .milliseconds(500))
            await store.receive(\.signedOutSettleTimerElapsed) {
                $0.isSignedOutSettling = false
            }
            expectNoDifference(store.state.isLoading, false)
            await store.finish()
        }
    }
}
