//
//  Settings.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import ComposableArchitecture
import Foundation
import os

@Reducer
struct Settings {
    enum AccountDeletionError: Error {
        case missingAuthorizationCode
        case timedOut
    }

    enum Alert: Equatable {
        case confirmAccountDeletion
        case confirmSignOut
    }

    enum DeletionStep: Equatable {
        case credentialRevoked
        case deleting
        case entriesDeleted
        case reauthenticating
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Settings.Alert>?
        var deletionStep: DeletionStep?
        let user: User

        var isDeletingAccount: Bool { deletionStep != nil }

        var isReauthenticating: Bool { deletionStep == .reauthenticating }
    }

    enum Action {
        case accountDeletionFailed(any Error)
        case alert(PresentationAction<Alert>)
        case appleCredentialReceived
        case appleCredentialRevoked
        #if DEBUG
        case debugAddMockEntriesButtonTapped
        case debugDeleteAllEntriesButtonTapped
        #endif
        case deleteAccountButtonTapped
        case dismissButtonTapped
        case entriesDeleted
        case signOutButtonTapped
        case signOutFailed(any Error)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .accountDeletionFailed(let error):
                guard state.deletionStep != .credentialRevoked else {
                    logger.error(
                        "Account deletion failed after the revoke attempt; signing out: \(error, privacy: .public)")
                    return signOut()
                }
                let hasDeletedEntries = state.deletionStep == .entriesDeleted
                state.deletionStep = nil
                if !error.isSignInWithAppleCancellation {
                    logger.error("Account deletion failed: \(error, privacy: .public)")
                    state.alert = hasDeletedEntries ? .accountDeletionUnfinished : .accountDeletionFailed
                }
                return .none

            case .alert(.presented(.confirmAccountDeletion)):
                state.deletionStep = .reauthenticating
                return deleteAccount(uid: state.user.uid)

            case .alert(.presented(.confirmSignOut)):
                return signOut()

            case .alert:
                return .none

            case .appleCredentialReceived:
                state.deletionStep = .deleting
                return .none

            case .appleCredentialRevoked:
                state.deletionStep = .credentialRevoked
                return .none

            #if DEBUG
            case .debugAddMockEntriesButtonTapped:
                return addMockEntries(uid: state.user.uid)

            case .debugDeleteAllEntriesButtonTapped:
                return deleteAllEntries(uid: state.user.uid)
            #endif

            case .deleteAccountButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                state.alert = .confirmAccountDeletion
                return .none

            case .dismissButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                return .run { _ in await dismiss() }

            case .entriesDeleted:
                state.deletionStep = .entriesDeleted
                return .none

            case .signOutButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                state.alert = .confirmSignOut
                return .none

            case .signOutFailed(let error):
                state.deletionStep = nil
                logger.error("Sign out failed: \(error, privacy: .public)")
                state.alert = .signOutFailed
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    #if DEBUG
    private func addMockEntries(uid: String) -> Effect<Action> {
        .run { _ in
            for entry in Entry.mocks {
                try await entriesClient.save(entry: entry, uid: uid)
            }
        } catch: { error, _ in
            logger.error("Adding the mock entries failed: \(error, privacy: .public)")
        }
    }

    private func deleteAllEntries(uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.deleteAll(uid: uid)
        } catch: { error, _ in
            logger.error("Deleting all the entries failed: \(error, privacy: .public)")
        }
    }
    #endif

    private func deleteAccount(uid: String) -> Effect<Action> {
        .run { send in
            let credential = try await signInWithAppleClient.requestCredential()
            guard let authorizationCode = credential.authorizationCode else {
                throw AccountDeletionError.missingAuthorizationCode
            }
            await send(.appleCredentialReceived)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await clock.sleep(for: .seconds(60))
                    throw AccountDeletionError.timedOut
                }
                group.addTask {
                    try await authClient.reauthenticate(credential: credential)
                    try Task.checkCancellation()
                    try await entriesClient.deleteAll(uid: uid)
                    await send(.entriesDeleted)
                    try Task.checkCancellation()
                    try await authClient.revokeAppleToken(authorizationCode: authorizationCode)
                    await send(.appleCredentialRevoked)
                    try Task.checkCancellation()
                    try await authClient.deleteAccount()
                }
                try await group.next()
                group.cancelAll()
            }
        } catch: { error, send in
            await send(.accountDeletionFailed(error))
        }
    }

    private func signOut() -> Effect<Action> {
        .run { _ in
            try await authClient.signOut()
        } catch: { error, send in
            await send(.signOutFailed(error))
        }
    }
}

extension AlertState where Action == Settings.Alert {
    static let accountDeletionFailed = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("Your account couldn't be deleted.")
    }

    static let accountDeletionUnfinished = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("Your account couldn't be fully deleted.")
    }

    static let confirmAccountDeletion = AlertState {
        TextState("Delete Account")
    } actions: {
        ButtonState(role: .destructive, action: .confirmAccountDeletion) {
            TextState("Delete")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Your account and all your entries will be permanently deleted. Are you sure?")
    }

    static let confirmSignOut = AlertState {
        TextState("Sign Out")
    } actions: {
        ButtonState(role: .destructive, action: .confirmSignOut) {
            TextState("Sign Out")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Are you sure you want to sign out?")
    }

    static let signOutFailed = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("You couldn't be signed out.")
    }
}

private let logger = Logger(category: "Settings")
