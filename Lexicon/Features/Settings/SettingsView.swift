//
//  SettingsView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

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
                        Text(store.user.email ?? "Unknown")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Button("Sign Out") {
                        store.send(.signOutButtonTapped)
                    }
                    Button("Delete Account", role: .destructive) {
                        store.send(.deleteAccountButtonTapped)
                    }
                }
                .disabled(store.isDeletingAccount)
                #if DEBUG
                Section("Debug") {
                    Button("Add Mock Entries") {
                        store.send(.debugAddMockEntriesButtonTapped)
                    }
                    Button("Delete All Entries", role: .destructive) {
                        store.send(.debugDeleteAllEntriesButtonTapped)
                    }
                }
                .disabled(store.isDeletingAccount)
                #endif
            }
            // Without this the navigation bar shows a back chevron at the root of the stack
            .navigationBarBackButtonHidden()
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .groupedBackground()
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .title) {
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.bold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss", systemImage: "xmark") {
                        store.send(.dismissButtonTapped)
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .disabled(store.isDeletingAccount)
                }
            }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
        .safeAreaInset(edge: .bottom) {
            Text("Version \(Bundle.main.appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom)
        }
        // The swipe stays disabled at every step so the user leaves Settings only through the Dismiss button
        .interactiveDismissDisabled()
    }
}

#Preview {
    SettingsView(
        store: Store(initialState: Settings.State(user: .mock)) {
            Settings()
        }
    )
}
