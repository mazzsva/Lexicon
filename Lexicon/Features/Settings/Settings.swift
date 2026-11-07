//
//  Settings.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import AccountKit
import ComposableArchitecture

@Reducer
struct Settings {
    @ObservableState
    struct State: Equatable {
        var account = AccountSettings.State()
        var isPresentingAbout = false
        let user: AccountUser
    }

    enum Action {
        case aboutPresentationChanged(Bool)
        case account(AccountSettings.Action)
        case dismissButtonTapped
        case infoButtonTapped
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Scope(state: \.account, action: \.account) {
            AccountSettings()
        }
        Reduce { state, action in
            switch action {
            case .aboutPresentationChanged(let isPresenting):
                state.isPresentingAbout = isPresenting
                return .none

            case .account:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

            case .infoButtonTapped:
                state.isPresentingAbout = true
                return .none
            }
        }
    }
}
