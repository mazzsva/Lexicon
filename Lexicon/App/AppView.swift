//
//  AppView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import AccountKit
import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AccountSession<Home>>

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if let sceneStore = store.scope(state: \.scene, action: \.scene) {
                switch sceneStore.case {
                case .home(let homeStore):
                    HomeView(store: homeStore)
                case .signIn(let signInStore):
                    SignInView(store: signInStore)
                }
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }
        }
        .loadingWindow(isVisible: store.isLoading, message: store.loadingReason.map(Self.loadingMessage))
        .sheet(isPresented: $store.isPresentingWelcome.sending(\.welcomePresentationChanged)) {
            WelcomeView { store.send(.welcomeContinueButtonTapped) }
                .interactiveDismissDisabled()
        }
        .task { await store.send(.task).finish() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { store.send(.appBecameActive) }
        }
    }

    static func loadingMessage(_ reason: SessionLoadingReason) -> String {
        switch reason {
        case .deletingAccount:
            String(localized: "Deleting your account…")
        case .signingIn:
            String(localized: "Signing in…")
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AccountSession<Home>.State()) {
            AccountSession<Home>()
        }
    )
}
