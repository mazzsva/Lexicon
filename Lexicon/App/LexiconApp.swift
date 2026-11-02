//
//  LexiconApp.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import AccountKit
import ComposableArchitecture
import FirebaseCore
import IssueReporting
import SwiftUI

@main
struct LexiconApp: App {
    @MainActor
    static let store = Store(initialState: AccountSession<Home>.State()) {
        AccountSession<Home>()
    }

    init() {
        guard !isTesting else { return }
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if !isTesting {
                AppView(store: Self.store)
            }
        }
    }
}
