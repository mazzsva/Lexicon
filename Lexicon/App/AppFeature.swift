//
//  AppFeature.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 26/07/26.
//

import ComposableArchitecture
import Foundation
import IssueReporting
import os

@Reducer
struct AppFeature {
    @Reducer
    enum Scene {
        case home(Home)
        case signIn(SignIn)
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.hasDismissedWelcome) var hasDismissedWelcome
        var isSignedOutSettling = false
        var scene: Scene.State?
        #if DEBUG
        @Shared(.showsWelcomeAtNextLaunch) var showsWelcomeAtNextLaunch
        #endif

        var hasLiveSession: Bool { scene.is(\.home) && !isDeletingAccount && !isSignedOutSettling }

        var isDeletingAccount: Bool { scene?.home?.isDeletingAccount ?? false }

        var isLoading: Bool {
            switch scene {
            case nil:
                return true
            case .home(let home):
                return isDeletingAccount || home.isLoadingFirstContent || isSignedOutSettling
            case .signIn(let signIn):
                return isSignedOutSettling || signIn.isAuthenticating
            }
        }

        var isPresentingWelcome: Bool {
            !hasDismissedWelcome && !isLoading
        }

        var loadingMessage: String? {
            switch scene {
            case .home(let home) where home.isDeletingAccount && !home.isReauthenticating:
                return String(localized: "Deleting your account…")
            case .home(let home) where home.isLoadingFirstContent:
                guard home.sessionOrigin == .freshSignIn else { return nil }
                return String(localized: "Signing in…")
            case .signIn(let signIn):
                guard signIn.step == .signingIn else { return nil }
                return String(localized: "Signing in…")
            case nil, .home:
                return nil
            }
        }
    }

    enum Action {
        case appBecameActive
        case appleCredentialRevoked
        case authUserChanged(User?)
        case scene(Scene.Action)
        case signedOutCoverTimerElapsed
        case signedOutSettleTimerElapsed
        case task
        case welcomeContinueButtonTapped
        case welcomePresentationChanged(Bool)
    }

    enum CancelID {
        case appleCredentialCheck
        case authObservation
        case credentialRevocationObservation
        case signedOutSettle
    }

    static let signedOutCoverDelay = Duration.milliseconds(300)
    static let signedOutSettleDelay = Duration.milliseconds(500)

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appBecameActive:
                guard state.hasLiveSession else { return .none }
                return verifyAppleCredential()

            case .appleCredentialRevoked:
                guard state.hasLiveSession else { return .none }
                logger.notice("Apple ID credential was revoked; signing out.")
                return .run { _ in
                    try await authClient.signOut()
                } catch: { error, _ in
                    logger.error("Sign out after Apple ID credential revocation failed: \(error, privacy: .public)")
                }

            case .authUserChanged(let user):
                return resolveAuthChange(&state, user: user)

            case .scene:
                return .none

            case .signedOutCoverTimerElapsed:
                guard state.isSignedOutSettling, state.scene.is(\.home) else { return .none }
                state.scene = .signIn(SignIn.State())
                return clearLocalData()

            case .signedOutSettleTimerElapsed:
                state.isSignedOutSettling = false
                return .none

            case .task:
                #if DEBUG
                if state.showsWelcomeAtNextLaunch {
                    state.$showsWelcomeAtNextLaunch.withLock { $0 = false }
                    state.$hasDismissedWelcome.withLock { $0 = false }
                }
                #endif
                return .merge(
                    observeAuthChanges(),
                    observeCredentialRevocations()
                )

            case .welcomeContinueButtonTapped, .welcomePresentationChanged(false):
                state.$hasDismissedWelcome.withLock { $0 = true }
                return .none

            case .welcomePresentationChanged(true):
                return .none
            }
        }
        .ifLet(\.scene, action: \.scene) {
            Scene.body
        }
        .onChange(of: \.isDeletingAccount) { wasDeletingAccount, isDeletingAccount in
            Reduce { state, _ in
                guard wasDeletingAccount, !isDeletingAccount, state.hasLiveSession else { return .none }
                return verifyAppleCredential()
            }
        }
    }

    private func clearLocalData() -> Effect<Action> {
        .run { _ in
            try await clearAppLocalData()
        } catch: { error, _ in
            logger.error("Clearing the local data failed: \(error, privacy: .public)")
            reportIssue(error, "Clearing the local data failed.")
        }
    }

    private func observeAuthChanges() -> Effect<Action> {
        .run { send in
            for await user in authClient.authStateChanges() {
                await send(.authUserChanged(user))
            }
        }
        .cancellable(id: CancelID.authObservation, cancelInFlight: true)
    }

    private func observeCredentialRevocations() -> Effect<Action> {
        .run { send in
            for await _ in signInWithAppleClient.credentialRevocations() {
                await send(.appleCredentialRevoked)
            }
        }
        .cancellable(id: CancelID.credentialRevocationObservation, cancelInFlight: true)
    }

    private func resolveAuthChange(_ state: inout State, user: User?) -> Effect<Action> {
        switch (state.scene, user) {
        case (nil, nil):
            state.scene = .signIn(SignIn.State())
            return clearLocalData()

        case (nil, .some(let user)):
            state.scene = .home(Home.State(user: user))
            return verifyAppleCredential()

        case (.signIn(let signIn), .some(let user)):
            let isFreshSignIn = signIn.isAuthenticating
            state.scene = .home(
                Home.State(user: user, sessionOrigin: isFreshSignIn ? .freshSignIn : .restored)
            )
            return isFreshSignIn ? .none : verifyAppleCredential()

        case (.signIn, nil):
            return .none

        case (.home(let home), .some(let user)) where home.user.uid == user.uid:
            return .none

        case (.home, .some):
            logger.notice("Auth changed accounts without signing out first; ending the session before the new one.")
            reportIssue("Auth changed accounts without signing out first.")
            state.isSignedOutSettling = false
            state.scene = nil
            return .concatenate(
                .merge(.cancel(id: CancelID.appleCredentialCheck), .cancel(id: CancelID.signedOutSettle)),
                clearLocalData(),
                .run { send in await send(.authUserChanged(authClient.currentUser())) }
            )

        case (.home, nil):
            state.isSignedOutSettling = true
            return .merge(
                .cancel(id: CancelID.appleCredentialCheck),
                settleSignOut()
            )
        }
    }

    private func settleSignOut() -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: Self.signedOutCoverDelay)
            await send(.signedOutCoverTimerElapsed)
            try await clock.sleep(for: Self.signedOutSettleDelay)
            await send(.signedOutSettleTimerElapsed)
        }
        .cancellable(id: CancelID.signedOutSettle, cancelInFlight: true)
    }

    private func verifyAppleCredential() -> Effect<Action> {
        .run { send in
            guard let appleUserID = authClient.appleUserID() else { return }
            let credentialState = await signInWithAppleClient.credentialState(userID: appleUserID)
            guard credentialState == .revoked else {
                if credentialState != .authorized {
                    logger.notice(
                        "Apple ID credential is \(credentialState.description, privacy: .public); keeping the session.")
                }
                return
            }
            await send(.appleCredentialRevoked)
        }
        .cancellable(id: CancelID.appleCredentialCheck, cancelInFlight: true)
    }
}

extension AppFeature.Scene.State: Equatable {}

private let logger = Logger(category: "AppFeature")
