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

    private static var aboutText: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleName"] as? String ?? "Lexicon"
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(name) \(version) (\(build))"
    }

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
                ToolbarItem(placement: .primaryAction) {
                    Button("About", systemImage: "info") {
                        store.send(.infoButtonTapped)
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .popover(isPresented: $store.isPresentingAbout.sending(\.aboutPresentationChanged)) {
                        Text(Self.aboutText)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                    }
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
