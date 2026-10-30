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
    enum Alert: Equatable {
        case confirmAccountDeletion
        case confirmSignOut
    }

    @Reducer
    enum Destination {
        case alert(AlertState<Settings.Alert>)
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
        #if DEBUG
        @Shared(.showsWelcomeAtNextLaunch) var showsWelcomeAtNextLaunch
        #endif
        let user: User
    }

    enum Action {
        #if DEBUG
        case debugAddMockEntriesButtonTapped
        case debugDeleteAllEntriesButtonTapped
        case debugResetWelcomeToggleChanged(Bool)
        #endif
        case delegate(Delegate)
        case deleteAccountButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case dismissButtonTapped
        case signOutButtonTapped
        case signOutFailed(any Error)

        @CasePathable
        enum Delegate {
            case didConfirmAccountDeletion
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.dismiss) var dismiss
    #if DEBUG
    @Dependency(\.entriesClient) var entriesClient
    #endif

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            #if DEBUG
            case .debugAddMockEntriesButtonTapped:
                return addMockEntries(uid: state.user.uid)

            case .debugDeleteAllEntriesButtonTapped:
                return deleteAllEntries(uid: state.user.uid)

            case .debugResetWelcomeToggleChanged(let isOn):
                state.$showsWelcomeAtNextLaunch.withLock { $0 = isOn }
                return .none
            #endif

            case .delegate:
                return .none

            case .deleteAccountButtonTapped:
                state.destination = .alert(.confirmAccountDeletion)
                return .none

            case .destination(.presented(.alert(.confirmAccountDeletion))):
                return .send(.delegate(.didConfirmAccountDeletion))

            case .destination(.presented(.alert(.confirmSignOut))):
                return .run { _ in
                    try await authClient.signOut()
                } catch: { error, send in
                    await send(.signOutFailed(error))
                }

            case .destination:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

            case .signOutButtonTapped:
                state.destination = .alert(.confirmSignOut)
                return .none

            case .signOutFailed(let error):
                logger.error("Sign out failed: \(error, privacy: .public)")
                state.destination = .alert(.signOutFailed)
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    #if DEBUG
    private func addMockEntries(uid: String) -> Effect<Action> {
        .run { _ in
            for entry in Entry.mocks {
                try await entriesClient.create(entry: entry, uid: uid)
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
}

extension Settings.Destination.State: Equatable {}

extension AlertState where Action == Settings.Alert {
    static func accountDeletionFailed(_ failure: AccountDeletion.Failure) -> AlertState {
        AlertState {
            TextState("Something Went Wrong")
        } message: {
            switch failure {
            case .connectionFailed:
                TextState("Your account couldn't be deleted. Check your connection and try again.")
            case .notDeleted:
                TextState("Your account couldn't be deleted.")
            case .notFullyDeleted:
                TextState("Your account couldn't be fully deleted.")
            case .notSignedOut:
                TextState("You couldn't be signed out.")
            }
        }
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
