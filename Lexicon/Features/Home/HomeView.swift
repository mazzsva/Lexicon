//
//  HomeView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<Home>

    @Namespace private var namespace

    var body: some View {
        let visibleEntries = store.filteredEntries
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            ScrollView {
                GlassEffectContainer(spacing: 0) {
                    LazyVStack(spacing: 16) {
                        ForEach(visibleEntries) { $entry in
                            NavigationLink(state: EntryDetail.State(entry: $entry)) {
                                EntryCardView(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .groupedBackground()
            .searchable(text: $store.searchText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .title) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Lexicon")
                            .font(.title)
                            .fontWeight(.bold)
                        SyncStatusLabel(entryCount: store.entryCount, status: store.syncStatus)
                    }
                }
                if store.entryCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            store.isShowingBookmarkedOnly ? "Show All Entries" : "Show Bookmarked Entries",
                            systemImage: store.isShowingBookmarkedOnly ? "bookmark.fill" : "bookmark"
                        ) {
                            store.send(.bookmarkFilterButtonTapped)
                        }
                        .labelStyle(.iconOnly)
                        .tint(store.isShowingBookmarkedOnly ? .bookmark : .secondary)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gear") {
                        store.send(.settingsButtonTapped)
                    }
                    .matchedTransitionSource(id: "settings", in: namespace)
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("New Entry", systemImage: "plus") {
                        store.send(.newEntryButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .overlay {
                if store.entries?.isEmpty == true {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "tray.fill",
                        description: Text("Tap the plus button to add an entry.")
                    )
                } else if store.entries != nil, visibleEntries.isEmpty, !store.searchText.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                } else if store.entries != nil, visibleEntries.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark.fill",
                        description: Text("Bookmark an entry to find it here.")
                    )
                }
            }
        } destination: { detailStore in
            EntryDetailView(store: detailStore)
        }
        .task { await store.send(.task).finish() }
        .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
        .sheet(
            item: $store.scope(state: \.destination?.createEntry, action: \.destination.createEntry)
        ) { formStore in
            EntryFormView(store: formStore)
        }
        .sheet(
            item: $store.scope(state: \.destination?.settings, action: \.destination.settings)
        ) { settingsStore in
            SettingsView(store: settingsStore)
                .navigationTransition(.zoom(sourceID: "settings", in: namespace))
        }
    }
}

#Preview("Populated") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        }
    )
}

#Preview("Empty") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        } withDependencies: {
            $0.entriesClient.entries = { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.empty)
                }
            }
        }
    )
}

#Preview("Syncing") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        } withDependencies: {
            $0.entriesClient.entries = { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.syncing)
                }
            }
        }
    )
}

#Preview("Offline") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        } withDependencies: {
            $0.networkMonitorClient.connectivityChanges = {
                AsyncStream { continuation in
                    continuation.yield(false)
                }
            }
        }
    )
}
