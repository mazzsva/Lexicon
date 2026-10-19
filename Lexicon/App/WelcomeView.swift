//
//  WelcomeView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 07/08/26.
//

import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                VStack(spacing: 0) {
                    Text("Welcome to")
                        .foregroundStyle(.tint)
                    Text("Lexicon")
                }
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 28) {
                    ForEach(WelcomeHighlight.all, id: \.systemImage) { highlight in
                        WelcomeHighlightRow(highlight: highlight)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.25), for: .alignment)
        .safeAreaBar(edge: .bottom) {
            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .groupedBackground()
    }
}

private struct WelcomeHighlight {
    let systemImage: String
    let text: LocalizedStringResource

    static let all = [
        WelcomeHighlight(
            systemImage: "books.vertical.fill",
            text: "Save any word or phrase with a definition in your own words."
        ),
        WelcomeHighlight(
            systemImage: "bookmark.fill",
            text: "Search by term or definition, and bookmark your favorites."
        ),
        WelcomeHighlight(
            systemImage: "apple.logo",
            text: "Sign in with Apple to keep every entry in your account."
        ),
    ]
}

private struct WelcomeHighlightRow: View {
    let highlight: WelcomeHighlight

    @ScaledMetric(relativeTo: .title) private var iconSize = 28

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: highlight.systemImage)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
                .frame(width: iconSize, height: iconSize)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text(highlight.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView {}
}
