//
//  Home.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import Foundation
import os

@Reducer
struct Home {
    @Reducer
    enum Destination {
        case accountDeletion(AccountDeletion)
        case alert(AlertState<Home.Alert>)
        case createEntry(EntryForm)
        case settings(Settings)
    }

    enum Alert: Equatable {}

    enum Failure: CaseIterable, Hashable {
        case entryDelete
        case entryImport
        case entrySave
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
        @Shared var entries: EntriesPhase
        var isOnline = true
        var isShowingBookmarkedOnly = false
        var isSyncing = true
        var path = StackState<EntryDetail.State>()
        var pendingFailures: Set<Failure> = []
        var searchText = ""
        let sessionOrigin: SessionOrigin
        let user: User

        enum EmptyState: Equatable {
            case bookmarks
            case entries
            case failed
            case search
        }

        @CasePathable
        @dynamicMemberLookup
        enum SessionOrigin: Equatable {
            case freshSignIn(isNewAccount: Bool)
            case restored
        }

        init(user: User, sessionOrigin: SessionOrigin = .restored) {
            _entries = Shared(value: .loading)
            self.sessionOrigin = sessionOrigin
            self.user = user
        }

        var canCreateEntries: Bool { entries.is(\.loaded) }

        var canFilterBookmarks: Bool { (entryCount ?? 0) > 0 }

        var emptyState: EmptyState? {
            switch entries {
            case .failed:
                return .failed
            case .loaded:
                guard filteredEntries.isEmpty else { return nil }
                if entryCount == 0 { return .entries }
                return searchText.isEmpty ? .bookmarks : .search
            case .loading:
                return nil
            }
        }

        var entryCount: Int? { entries.loaded?.count }

        var filteredEntries: [SharedReader<Entry>] {
            guard let entries = SharedReader(SharedReader($entries).loaded) else { return [] }
            return Array(entries).filter { isVisible($0.wrappedValue) }
        }

        var isDeletingAccount: Bool { destination.is(\.accountDeletion) }

        var isFreshSignIn: Bool { sessionOrigin.is(\.freshSignIn) }

        var isLoadingFirstEntries: Bool { entries.is(\.loading) }

        var isReauthenticating: Bool { destination?.accountDeletion?.step == .reauthenticating }

        var syncStatus: SyncStatus {
            guard isOnline else { return .offline }
            return isSyncing ? .syncing : .synced
        }

        fileprivate var canPresentFailure: Bool {
            destination == nil && path.allSatisfy { $0.destination == nil }
        }

        private func isVisible(_ entry: Entry) -> Bool {
            if isShowingBookmarkedOnly, !entry.isBookmarked { return false }
            guard !searchText.isEmpty else { return true }
            return entry.term.localizedStandardContains(searchText)
                || entry.definition.localizedStandardContains(searchText)
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case bookmarkFilterButtonTapped
        case connectivityChanged(Bool)
        case destination(PresentationAction<Destination.Action>)
        case entriesImportFailed(any Error)
        case entriesRetryTimerElapsed
        case entriesStreamFailed
        case entriesUpdated(EntriesSnapshot)
        case entryDeleteFailed(Entry.ID, any Error)
        case entrySaveFailed(Entry.ID, any Error)
        case newEntryButtonTapped
        case path(StackActionOf<EntryDetail>)
        case settingsButtonTapped
        case task
    }

    enum CancelID {
        case connectivitySubscription
        case entriesSubscription
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.networkMonitorClient) var networkMonitorClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .bookmarkFilterButtonTapped:
                state.isShowingBookmarkedOnly.toggle()
                return .none

            case .connectivityChanged(let isOnline):
                state.isOnline = isOnline
                return .none

            case .destination(.presented(.accountDeletion(.delegate(.didCancel)))):
                presentSettings(&state)
                return .none

            case .destination(.presented(.accountDeletion(.delegate(.didFail(let failure))))):
                presentSettings(&state, destination: .alert(.accountDeletionFailed(failure)))
                return .none

            case .destination(.presented(.createEntry(.delegate(.didSubmit(let entry))))):
                state.destination = nil
                return .merge(
                    .run { _ in await hapticsClient.success() },
                    create(entry, uid: state.user.uid)
                )

            case .destination(.presented(.settings(.delegate(.didConfirmAccountDeletion)))):
                state.destination = .accountDeletion(AccountDeletion.State(uid: state.user.uid))
                return .send(.destination(.presented(.accountDeletion(.deletionConfirmed))))

            case .destination(.presented(.settings(.delegate(.didImport(let entries))))):
                state.destination = nil
                return .merge(
                    .run { _ in await hapticsClient.success() },
                    importEntries(entries, uid: state.user.uid)
                )

            case .destination:
                return .none

            case .entriesImportFailed(let error):
                logger.error("Importing the entries failed: \(error, privacy: .public)")
                state.pendingFailures.insert(.entryImport)
                return .none

            case .entriesRetryTimerElapsed:
                return subscribeToEntries(state)

            case .entriesStreamFailed:
                state.isSyncing = true
                let retry: Effect<Action> =
                    .run { send in
                        try await clock.sleep(for: .seconds(5))
                        await send(.entriesRetryTimerElapsed)
                    }
                    .cancellable(id: CancelID.entriesSubscription, cancelInFlight: true)
                guard state.isLoadingFirstEntries else { return retry }
                state.$entries.withLock { $0 = .failed }
                return .merge(retry, celebrateFirstLoad(state))

            case .entriesUpdated(let snapshot):
                let isFirstLoad = state.isLoadingFirstEntries
                state.isSyncing = snapshot.isSyncing
                let entries = IdentifiedArray(uniqueElements: snapshot.entries)
                state.$entries.withLock { $0 = .loaded(entries) }
                if entries.isEmpty {
                    state.isShowingBookmarkedOnly = false
                }
                for id in Array(state.path.ids) {
                    guard
                        let entryID = state.path[id: id]?.entry.id,
                        entries[id: entryID] == nil
                    else { continue }
                    state.path.pop(from: id)
                }
                guard isFirstLoad else { return .none }
                return celebrateFirstLoad(state)

            case .entryDeleteFailed(let id, let error):
                logger.error("Deleting entry \(id, privacy: .public) failed: \(error, privacy: .public)")
                state.pendingFailures.insert(.entryDelete)
                return .none

            case .entrySaveFailed(let id, let error):
                logger.error("Saving entry \(id, privacy: .public) failed: \(error, privacy: .public)")
                state.pendingFailures.insert(.entrySave)
                return .none

            case .newEntryButtonTapped:
                guard state.canCreateEntries else { return .none }
                state.destination = .createEntry(EntryForm.State())
                return .none

            case .path(.element(id: let id, action: .delegate(.didDelete(let entryID)))):
                state.path.pop(from: id)
                return .merge(
                    .run { _ in await hapticsClient.warning() },
                    delete(entryID, uid: state.user.uid)
                )

            case .path(.element(id: _, action: .delegate(.didUpdate(let entry)))):
                return update(entry, uid: state.user.uid)

            case .path:
                return .none

            case .settingsButtonTapped:
                presentSettings(&state)
                return .none

            case .task:
                return .merge(
                    observeConnectivity(),
                    subscribeToEntries(state)
                )
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .forEach(\.path, action: \.path) {
            EntryDetail()
        }
        Reduce { state, _ in
            guard
                state.canPresentFailure,
                let failure = Failure.allCases.first(where: state.pendingFailures.contains)
            else { return .none }
            state.pendingFailures.remove(failure)
            state.destination = .alert(.failed(failure))
            return .none
        }
    }

    // The haptic welcomes the user into the app, so it plays even when the entries fail to load
    private func celebrateFirstLoad(_ state: State) -> Effect<Action> {
        state.isFreshSignIn ? .run { _ in await hapticsClient.success() } : .none
    }

    private func create(_ entry: Entry, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.create(entry: entry, uid: uid)
        } catch: { error, send in
            await send(.entrySaveFailed(entry.id, error))
        }
    }

    private func delete(_ id: Entry.ID, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.delete(id: id, uid: uid)
        } catch: { error, send in
            await send(.entryDeleteFailed(id, error))
        }
    }

    private func importEntries(_ entries: [Entry], uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.createAll(entries: entries, uid: uid)
        } catch: { error, send in
            await send(.entriesImportFailed(error))
        }
    }

    private func observeConnectivity() -> Effect<Action> {
        .run { send in
            for await isOnline in networkMonitorClient.connectivityChanges() {
                await send(.connectivityChanged(isOnline))
            }
        }
        .cancellable(id: CancelID.connectivitySubscription, cancelInFlight: true)
    }

    private func presentSettings(_ state: inout State, destination: Settings.Destination.State? = nil) {
        state.destination = .settings(
            Settings.State(destination: destination, entries: SharedReader(state.$entries), user: state.user)
        )
    }

    private func subscribeToEntries(_ state: State) -> Effect<Action> {
        let uid = state.user.uid
        return
            .run { send in
                do {
                    let snapshots = await entriesClient.entries(uid: uid)
                    for try await snapshot in snapshots {
                        await send(.entriesUpdated(snapshot))
                    }
                } catch {
                    logger.error("Entries stream failed: \(error, privacy: .public)")
                    await send(.entriesStreamFailed)
                }
            }
            .cancellable(id: CancelID.entriesSubscription, cancelInFlight: true)
    }

    private func update(_ entry: Entry, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.update(entry: entry, uid: uid)
        } catch: { error, send in
            await send(.entrySaveFailed(entry.id, error))
        }
    }
}

extension Home.Destination.State: Equatable {}

extension AlertState where Action == Home.Alert {
    static func failed(_ failure: Home.Failure) -> AlertState {
        AlertState {
            TextState("Something Went Wrong")
        } message: {
            switch failure {
            case .entryDelete:
                TextState("Your entry couldn't be deleted.")
            case .entryImport:
                TextState("Some entries couldn't be imported.")
            case .entrySave:
                TextState("Your entry couldn't be saved.")
            }
        }
    }
}

private let logger = Logger(category: "Home")
