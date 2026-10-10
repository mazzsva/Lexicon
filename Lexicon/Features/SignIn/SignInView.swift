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
            Image(.appIcon)
                .resizable()
                .scaleEffect(1.035)
                .mask { Image(.appIcon).resizable() }
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .mask {
                        ZStack {
                            Image(.appIcon).resizable()
                            Image(.appIcon).resizable().scaleEffect(63 / 64).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                }
                .frame(width: 128, height: 128)
                .shadow(color: .bookmark.opacity(0.35), radius: 18)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RadialGradient(
                        stops: [
                            .init(color: .bookmark.opacity(0.25), location: 0),
                            .init(color: .bookmark.opacity(0.14), location: 0.35),
                            .init(color: .bookmark.opacity(0.05), location: 0.7),
                            .init(color: .bookmark.opacity(0), location: 1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                }

            VStack(spacing: 6) {
                Text("Lexicon")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Text("Make every word yours.")
                    .foregroundStyle(.secondary)
                AppleSignInButton {
                    store.send(.signInButtonTapped)
                }
                .disabled(store.isAuthenticating)
                .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 30)
            .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 32), isUniform: true))
            .padding([.horizontal, .bottom], 10)
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
