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
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        guard !isTesting else { return }
        FirebaseApp.configure()
        prepareDependencies {
            $0.userDataClient = UserDataClient(
                deleteAll: { uid, didDeleteSomeData in
                    try await FirestoreStorage.shared.deleteAll(uid: uid)
                    await didDeleteSomeData()
                }
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            if !isTesting {
                AppView(store: Self.store)
            }
        }
    }
}
