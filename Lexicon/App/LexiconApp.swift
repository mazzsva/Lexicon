//
//  LexiconApp.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import ComposableArchitecture
import FirebaseCore
import SwiftUI

@main
struct LexiconApp: App {
    @MainActor
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
        }
    }
}
