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
                    Label {
                        Text(store.user.email ?? String(localized: "Unknown"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "apple.logo")
                            .accessibilityLabel("Sign in with Apple")
                    }
                }
                .listRowBackground(Color.appSurface)
                Section {
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        store.send(.account(.signOutButtonTapped))
                    }
                }
                .listRowBackground(Color.appSurface)
                .listSectionSpacing(.custom(8))
                Section {
                    Button(role: .destructive) {
                        store.send(.account(.deleteAccountButtonTapped))
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Color.appSurface)
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
