//
//  AppView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

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
        .loadingWindow(isVisible: store.isLoading, message: store.loadingMessage)
        .sheet(isPresented: $store.isPresentingWelcome.sending(\.welcomePresentationChanged)) {
            WelcomeView { store.send(.welcomeContinueButtonTapped) }
                .interactiveDismissDisabled()
        }
        .task { await store.send(.task).finish() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { store.send(.appBecameActive) }
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
