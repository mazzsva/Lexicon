//
//  LexiconApp.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import ComposableArchitecture
import FirebaseCore
import Foundation
import SwiftUI

@main
struct LexiconApp: App {
    @MainActor
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        guard !isRunningTests else { return }
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if !isRunningTests {
                AppView(store: Self.store)
            }
        }
    }
}

private var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
