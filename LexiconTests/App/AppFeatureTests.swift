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
    // Firebase and Apple report the two events that can start or end a session
    @Test
    func theTaskObservesTheAuthChangesAndTheCredentialRevocations() async {
        let authChanges = AsyncStream<User?>.makeStream()
        let revocations = AsyncStream<Void>.makeStream()

        await confirmation("Signs the user out") { signsOut in
            let store = TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.authClient.appleUserID = { nil }
                $0.authClient.authStateChanges = { authChanges.stream }
                $0.authClient.signOut = { signsOut() }
                $0.signInWithAppleClient.credentialRevocations = { revocations.stream }
            }

            await store.send(.task)

            authChanges.continuation.yield(.mock)
            await store.receive(\.authUserChanged) {
                $0.scene = .home(Home.State(user: .mock))
            }

            revocations.continuation.yield()
            await store.receive(\.appleCredentialInvalidated)

            authChanges.continuation.finish()
            revocations.continuation.finish()
            await store.finish()
        }
    }

    // Apple can revoke the credential while the app does not run
    @Test
    func aSignedInUserAtLaunchRoutesToHomeAndVerifiesTheCredential() async {
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

    // Firestore keeps its cache on disk, so the app removes the entries of the last user
    @Test
    func aSignedOutUserAtLaunchRoutesToSignInAndClearsTheLocalData() async {
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

    // The welcome must not cover the loading screen at launch
    @Test
    func theWelcomeIsPresentedOnlyOnceTheAppIsReady() {
        var state = AppFeature.State()
        #expect(!state.isPresentingWelcome)

        state.scene = .signIn(SignIn.State())
        #expect(state.isPresentingWelcome)

        state.$hasDismissedWelcome.withLock { $0 = true }
        #expect(!state.isPresentingWelcome)
    }

    // App storage keeps the flag, so the welcome does not return at the next launch
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

    // Firebase reports no user while the sign in is in progress
    @Test
    func aSignedOutUserOnTheSignInIsIgnored() async {
        var state = AppFeature.State()
        state.scene = .signIn(SignIn.State())

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.authUserChanged(nil))
    }

    // The sign in scene shows first at launch, so a restored session comes through it
    @Test
    func aRestoredSessionRoutesToHomeAndVerifiesTheCredential() async {
        var state = AppFeature.State()
        state.scene = .signIn(SignIn.State())

        await confirmation("Verifies the Apple credential") { verifiesCredential in
            let store = TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.authClient.appleUserID = { "apple-user" }
                $0.signInWithAppleClient.credentialState = { _ in
                    verifiesCredential()
                    return .authorized
                }
            }

            await store.send(.authUserChanged(.mock)) {
                $0.scene = .home(Home.State(user: .mock, sessionOrigin: .restored))
            }
            await store.finish()
        }
    }

    // Apple authorized the user a moment ago, so the app does not check the credential again
    @Test
    func finishingTheSignInRoutesToHomeAsAFreshSignIn() async {
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

    // Firebase sends the same user again after each token refresh
    @Test
    func theSameSignedInUserIsIgnored() async {
        var state = AppFeature.State()
        state.scene = .home(Home.State(user: .mock))

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.authUserChanged(.mock))
    }

    // The user can revoke the Apple ID while the app is in the background
    @Test
    func becomingActiveSignsTheUserOutWhenTheCredentialIsRevoked() async {
        var state = AppFeature.State()
        state.scene = .home(Home.State(user: .mock))

        await confirmation("Signs the user out") { signsOut in
            let store = TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.authClient.appleUserID = { "apple-user" }
                $0.authClient.signOut = { signsOut() }
                $0.signInWithAppleClient.credentialState = { _ in .revoked }
            }

            await store.send(.appBecameActive)
            await store.receive(\.appleCredentialInvalidated)
            await store.finish()
        }
    }

    // The deletion revokes the credential itself, and a sign out would stop it
    @Test
    func theCredentialChecksAreIgnoredWhileDeletingTheAccount() async {
        var settings = Settings.State(user: .mock)
        settings.deletionStep = .credentialRevoked
        var home = Home.State(user: .mock)
        home.destination = .settings(settings)
        var state = AppFeature.State()
        state.scene = .home(home)

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.appBecameActive)
        await store.send(.appleCredentialInvalidated(.revoked))
    }

    // The message follows the step in progress, and a system sheet gets none
    @Test
    func theLoadingMessageDescribesWhatTheAppIsDoing() {
        var state = AppFeature.State()
        #expect(state.isLoading)
        expectNoDifference(state.loadingMessage, nil)

        var signIn = SignIn.State()
        signIn.step = .signingIn(isNewAccount: false)
        state.scene = .signIn(signIn)
        #expect(state.isLoading)
        expectNoDifference(state.loadingMessage, "Signing in…")

        signIn.step = .signingIn(isNewAccount: true)
        state.scene = .signIn(signIn)
        expectNoDifference(state.loadingMessage, "Creating your account…")

        var settings = Settings.State(user: .mock)
        settings.deletionStep = .reauthenticating
        var home = Home.State(user: .mock)
        home.destination = .settings(settings)
        state.scene = .home(home)
        #expect(state.isLoading)
        expectNoDifference(state.loadingMessage, nil)

        settings.deletionStep = .deleting
        home.destination = .settings(settings)
        state.scene = .home(home)
        expectNoDifference(state.loadingMessage, "Deleting your account…")

        state.scene = .home(
            Home.State(user: .mock, sessionOrigin: .freshSignIn(isNewAccount: false))
        )
        #expect(state.isLoading)
        expectNoDifference(state.loadingMessage, "Signing in…")

        signIn.step = .awaitingAuthorization
        state.scene = .signIn(signIn)
        #expect(state.isLoading)
        expectNoDifference(state.loadingMessage, nil)
    }

    // The Apple sheet covers the app, so the message waits for the deletion to start
    @Test
    func theLoadingMessageAppearsOnceTheAccountDeletionStarts() async {
        var state = AppFeature.State()
        state.scene = .home(Home.State(user: .mock))

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.authClient.reauthenticate = { _ in try await Task.never() }
            $0.continuousClock = TestClock()
            $0.signInWithAppleClient.requestCredential = { .mock }
        }
        store.exhaustivity = .off

        await store.send(\.scene.home.settingsButtonTapped)
        await store.send(\.scene.home.destination.settings.deleteAccountButtonTapped)
        await store.send(
            .scene(.home(.destination(.presented(.settings(.alert(.presented(.confirmAccountDeletion)))))))
        )
        expectNoDifference(store.state.loadingMessage, nil)

        await store.receive(\.scene.home.destination.settings.appleCredentialReceived)
        expectNoDifference(store.state.loadingMessage, "Deleting your account…")
    }

    // Auth must not change accounts without a sign out, so the app also reports an issue
    @Test
    func switchingAccountsRestartsTheSession() async {
        let other = User(email: "other@example.com", uid: "other-uid")
        var state = AppFeature.State()
        state.scene = .home(Home.State(user: .mock))

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.authClient.appleUserID = { nil }
            $0.entriesClient.clearLocalData = {}
        }

        await withExpectedIssue {
            await store.send(.authUserChanged(other)) {
                $0.scene = nil
            }
        }
        await store.receive(\.authUserChanged) {
            $0.scene = .home(Home.State(user: other))
        }
        await store.finish()
    }

    // The loading state hides the sign in controls while the local data disappears
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
