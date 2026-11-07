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
        let user: AccountUser
    }

    enum Action {
        case account(AccountSettings.Action)
        case dismissButtonTapped
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Scope(state: \.account, action: \.account) {
            AccountSettings()
        }
        Reduce { state, action in
            switch action {
            case .account:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }
            }
        }
    }
}
