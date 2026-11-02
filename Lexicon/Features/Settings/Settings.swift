//
//  Settings.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import AccountKit
import ComposableArchitecture
import Foundation
import os

@Reducer
struct Settings {
    @ObservableState
    struct State: Equatable {
        var account = AccountSettings.State()
        #if DEBUG
        @Shared(.showsWelcomeAtNextLaunch) var showsWelcomeAtNextLaunch
        #endif
        let user: AccountUser
    }

    enum Action {
        case account(AccountSettings.Action)
        #if DEBUG
        case debugAddMockEntriesButtonTapped
        case debugDeleteAllEntriesButtonTapped
        case debugResetWelcomeToggleChanged(Bool)
        #endif
        case dismissButtonTapped
    }

    @Dependency(\.dismiss) var dismiss
    #if DEBUG
    @Dependency(\.entriesClient) var entriesClient
    #endif

    var body: some Reducer<State, Action> {
        Scope(state: \.account, action: \.account) {
            AccountSettings()
        }
        Reduce { state, action in
            switch action {
            case .account:
                return .none

            #if DEBUG
            case .debugAddMockEntriesButtonTapped:
                return addMockEntries(uid: state.user.uid)

            case .debugDeleteAllEntriesButtonTapped:
                return deleteAllEntries(uid: state.user.uid)

            case .debugResetWelcomeToggleChanged(let isOn):
                state.$showsWelcomeAtNextLaunch.withLock { $0 = isOn }
                return .none
            #endif

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }
            }
        }
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

private let logger = Logger(category: "Settings")
