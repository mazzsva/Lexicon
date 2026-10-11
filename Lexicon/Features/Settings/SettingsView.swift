//
//  SettingsView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

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
                }
                Section {
                    ShareLink(
                        item: EntriesArchive.Export(entries: Array(store.entries ?? [])),
                        preview: SharePreview("Lexicon Entries")
                    ) {
                        Text("Export Entries")
                    }
                    .disabled(!store.canExportEntries)
                    Button {
                        store.send(.importEntriesButtonTapped)
                    } label: {
                        HStack {
                            Text("Import Entries")
                            Spacer()
                            if store.isLoadingImportFile {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!store.canImportEntries)
                }
                Section {
                    Button("Sign Out") {
                        store.send(.signOutButtonTapped)
                    }
                    Button("Delete Account", role: .destructive) {
                        store.send(.deleteAccountButtonTapped)
                    }
                }
                #if DEBUG
                Section("Developer") {
                    Button {
                        store.send(.debugAddMockEntriesButtonTapped)
                    } label: {
                        Text(verbatim: "Save Entry.mocks")
                    }
                    Button(role: .destructive) {
                        store.send(.debugDeleteAllEntriesButtonTapped)
                    } label: {
                        Text(verbatim: "Call deleteAll(uid:)")
                    }
                    Toggle(isOn: $store.showsWelcomeAtNextLaunch.sending(\.debugResetWelcomeToggleChanged)) {
                        Text(verbatim: "Reset hasDismissedWelcome")
                    }
                }
                #endif
            }
            // Without this the navigation bar shows a back chevron at the root of the stack
            .navigationBarBackButtonHidden()
            .scrollDisabled(true)
            .listSectionSpacing(.compact)
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
                }
            }
            .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
            .fileImporter(
                isPresented: $store.isFileImporterPresented.sending(\.fileImporterPresentationChanged),
                allowedContentTypes: [.json]
            ) { result in
                store.send(.importFilePicked(result))
            }
        }
        .safeAreaBar(edge: .bottom) {
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
        store: Store(
            initialState: Settings.State(
                entries: SharedReader(value: IdentifiedArray(uniqueElements: Entry.mocks)),
                user: .mock
            )
        ) {
            Settings()
        }
    )
}
