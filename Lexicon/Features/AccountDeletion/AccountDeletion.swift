//
//  AccountDeletion.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import ComposableArchitecture
import Foundation
import os

@Reducer
struct AccountDeletion {
    enum Failure: Equatable {
        case notDeleted
        case notFullyDeleted
        case notSignedOut
    }

    enum Step: Equatable {
        case credentialRevoked
        case deleting
        case entriesDeleted
        case reauthenticating
    }

    @ObservableState
    struct State: Equatable {
        var step = Step.reauthenticating
        let uid: String
    }

    enum Action {
        case accountDeleted
        case appleCredentialReceived(AppleCredential)
        case appleCredentialRevoked
        case delegate(Delegate)
        case deletionConfirmed
        case deletionFailed(any Error)
        case deletionTimerElapsed
        case entriesDeleted
        case signOutFailed(any Error)

        @CasePathable
        enum Delegate {
            case didCancel
            case didFail(Failure)
        }
    }

    enum CancelID {
        case deletion
    }

    enum DeletionError: Error {
        case missingAuthorizationCode
        case timedOut
    }

    static let timeout = Duration.seconds(60)

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .accountDeleted:
                return .cancel(id: CancelID.deletion)

            case .appleCredentialReceived(let credential):
                guard let authorizationCode = credential.authorizationCode else {
                    return fail(&state, error: DeletionError.missingAuthorizationCode)
                }
                state.step = .deleting
                return
                    .merge(
                        deleteAccount(credential: credential, authorizationCode: authorizationCode, uid: state.uid),
                        .run { send in
                            try await clock.sleep(for: Self.timeout)
                            await send(.deletionTimerElapsed)
                        }
                    )
                    .cancellable(id: CancelID.deletion)

            case .appleCredentialRevoked:
                state.step = .credentialRevoked
                return .none

            case .delegate:
                return .none

            case .deletionConfirmed:
                return
                    .run { send in
                        do {
                            await send(.appleCredentialReceived(try await signInWithAppleClient.requestCredential()))
                        } catch {
                            await send(.deletionFailed(error))
                        }
                    }
                    .cancellable(id: CancelID.deletion)

            case .deletionFailed(let error):
                return fail(&state, error: error)

            case .deletionTimerElapsed:
                return fail(&state, error: DeletionError.timedOut)

            case .entriesDeleted:
                state.step = .entriesDeleted
                return .none

            case .signOutFailed(let error):
                logger.error("Sign out failed: \(error, privacy: .public)")
                return .send(.delegate(.didFail(.notSignedOut)))
            }
        }
    }

    private func deleteAccount(credential: AppleCredential, authorizationCode: String, uid: String) -> Effect<Action> {
        .run { send in
            try await authClient.reauthenticate(credential: credential)
            try Task.checkCancellation()
            try await entriesClient.deleteAll(uid: uid)
            await send(.entriesDeleted)
            try Task.checkCancellation()
            try await authClient.revokeAppleToken(authorizationCode: authorizationCode)
            await send(.appleCredentialRevoked)
            try Task.checkCancellation()
            try await authClient.deleteAccount()
            await send(.accountDeleted)
        } catch: { error, send in
            await send(.deletionFailed(error))
        }
    }

    private func fail(_ state: inout State, error: any Error) -> Effect<Action> {
        guard state.step != .credentialRevoked else {
            logger.error("Account deletion failed after the revoke; signing out: \(error, privacy: .public)")
            return .merge(
                .cancel(id: CancelID.deletion),
                .run { _ in
                    try await authClient.signOut()
                } catch: { error, send in
                    await send(.signOutFailed(error))
                }
            )
        }
        guard !error.isSignInWithAppleCancellation else {
            return .merge(.cancel(id: CancelID.deletion), .send(.delegate(.didCancel)))
        }
        logger.error("Account deletion failed: \(error, privacy: .public)")
        return .merge(
            .cancel(id: CancelID.deletion),
            .send(.delegate(.didFail(state.step == .entriesDeleted ? .notFullyDeleted : .notDeleted)))
        )
    }
}

private let logger = Logger(category: "AccountDeletion")
