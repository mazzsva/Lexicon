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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glowColors = GenerationGlowSurface.palette(for: colorScheme)
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
                .background {
                    AngularGradient(
                        colors: glowColors + glowColors.reversed().dropFirst(),
                        center: .center,
                        angle: .degrees(315)
                    )
                    .mask { Image(.appIcon).resizable() }
                    .scaleEffect(1.3)
                    .blur(radius: 28)
                    .opacity(colorScheme == .dark ? 0.85 : 0.7)
                }
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 6) {
                Text("Lexicon")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
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
