//
//  SettingsView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import AccountKit
import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<Settings>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                        Text(store.user.email ?? String(localized: "Unknown"))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text("Using Sign in with Apple")
                }
                Section {
                    Button("Sign Out") {
                        store.send(.account(.signOutButtonTapped))
                    }
                }
                .listSectionSpacing(.custom(8))
                Section {
                    Button("Delete Account", role: .destructive) {
                        store.send(.account(.deleteAccountButtonTapped))
                    }
                }
            }
            // Without this the navigation bar shows a back chevron at the root of the stack
            .navigationBarBackButtonHidden()
            .scrollBounceBehavior(.basedOnSize)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .groupedBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") {
                        store.send(.dismissButtonTapped)
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                }
            }
            .alert($store.scope(state: \.account.alert, action: \.account.alert))
        }
    }
}

#Preview {
    SettingsView(
        store: Store(initialState: Settings.State(user: .mock)) {
            Settings()
        }
    )
}
