//
//  SignInView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import ComposableArchitecture
import SwiftUI

struct SignInView: View {
    @Bindable var store: StoreOf<SignIn>

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AppleSignInButton {
                store.send(.signInButtonTapped)
            }
            .disabled(store.isAuthenticating)
            .padding(10)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .groupedBackground()
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

#Preview {
    SignInView(
        store: Store(initialState: SignIn.State()) {
            SignIn()
        }
    )
}
