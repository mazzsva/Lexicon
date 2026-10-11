//
//  Settings.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import ComposableArchitecture
import Foundation
import os

@Reducer
struct Settings {
    enum Alert: Equatable {
        case confirmAccountDeletion
        case confirmImport([Entry])
        case confirmSignOut
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Settings.Alert>?
        @SharedReader var entries: IdentifiedArrayOf<Entry>?
        var isFileImporterPresented = false
        #if DEBUG
        @Shared(.showsWelcomeAtNextLaunch) var showsWelcomeAtNextLaunch
        #endif
        let user: User

        init(
            alert: AlertState<Settings.Alert>? = nil,
            entries: SharedReader<IdentifiedArrayOf<Entry>?>,
            user: User
        ) {
            self.alert = alert
            _entries = entries
            self.user = user
        }

        var canExportEntries: Bool { !(entries?.isEmpty ?? true) }

        var canImportEntries: Bool { entries != nil }
    }

    enum Action {
        case alert(PresentationAction<Alert>)
        #if DEBUG
        case debugAddMockEntriesButtonTapped
        case debugDeleteAllEntriesButtonTapped
        case debugResetWelcomeToggleChanged(Bool)
        #endif
        case delegate(Delegate)
        case deleteAccountButtonTapped
        case dismissButtonTapped
        case fileImporterPresentationChanged(Bool)
        case importEntriesButtonTapped
        case importFileLoaded(Result<[EntriesArchive.Record], any Error>)
        case importFilePicked(Result<URL, any Error>)
        case signOutButtonTapped
        case signOutFailed(any Error)

        @CasePathable
        enum Delegate {
            case didConfirmAccountDeletion
            case didImport([Entry])
        }
    }

    enum CancelID {
        case importFileLoad
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.date.now) var now
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.fileClient) var fileClient
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .alert(.presented(.confirmAccountDeletion)):
                return .send(.delegate(.didConfirmAccountDeletion))

            case .alert(.presented(.confirmImport(let entries))):
                return .send(.delegate(.didImport(entries)))

            case .alert(.presented(.confirmSignOut)):
                return .merge(
                    .cancel(id: CancelID.importFileLoad),
                    .run { _ in
                        try await authClient.signOut()
                    } catch: { error, send in
                        await send(.signOutFailed(error))
                    }
                )

            case .alert:
                return .none

            #if DEBUG
            case .debugAddMockEntriesButtonTapped:
                return addMockEntries(uid: state.user.uid)

            case .debugDeleteAllEntriesButtonTapped:
                return deleteAllEntries(uid: state.user.uid)

            case .debugResetWelcomeToggleChanged(let isOn):
                state.$showsWelcomeAtNextLaunch.withLock { $0 = isOn }
                return .none
            #endif

            case .delegate:
                return .none

            case .deleteAccountButtonTapped:
                state.alert = .confirmAccountDeletion
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

            case .fileImporterPresentationChanged(let isPresented):
                state.isFileImporterPresented = isPresented
                return .none

            case .importEntriesButtonTapped:
                guard state.canImportEntries else { return .none }
                state.isFileImporterPresented = true
                return .none

            case .importFileLoaded(.failure(let error)):
                logger.error("Loading the import file failed: \(error, privacy: .public)")
                state.alert = .importFailed(error)
                return .none

            case .importFileLoaded(.success(let records)):
                guard let existing = state.entries else { return .none }
                let entriesImport = EntriesArchive.Import(
                    records: records,
                    existing: existing.elements,
                    now: now,
                    uuid: { uuid() }
                )
                state.alert =
                    entriesImport.entries.isEmpty
                    ? entriesImport.duplicateCount > 0 ? .importHasOnlyDuplicates : .importHasNoEntries
                    : .confirmImport(entriesImport)
                return .none

            case .importFilePicked(.failure(let error)):
                logger.error("Picking the import file failed: \(error, privacy: .public)")
                state.alert = .importFailed(error)
                return .none

            case .importFilePicked(.success(let url)):
                return
                    .run { send in
                        do {
                            let data = try await fileClient.read(url: url, maximumSize: EntriesArchive.maximumFileSize)
                            await send(.importFileLoaded(.success(try EntriesArchive.records(from: data))))
                        } catch {
                            await send(.importFileLoaded(.failure(error)))
                        }
                    }
                    .cancellable(id: CancelID.importFileLoad, cancelInFlight: true)

            case .signOutButtonTapped:
                state.alert = .confirmSignOut
                return .none

            case .signOutFailed(let error):
                logger.error("Sign out failed: \(error, privacy: .public)")
                state.alert = .signOutFailed
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    #if DEBUG
    private func addMockEntries(uid: String) -> Effect<Action> {
        .run { _ in
            for entry in Entry.mocks {
                try await entriesClient.save(entry: entry, uid: uid)
            }
        } catch: { error, _ in
            logger.error("Adding the mock entries failed: \(error, privacy: .public)")
        }
    }

    private func deleteAllEntries(uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.deleteAll(uid: uid)
        } catch: { error, _ in
            logger.error("Deleting all the entries failed: \(error, privacy: .public)")
        }
    }
    #endif
}

extension AlertState where Action == Settings.Alert {
    static func accountDeletionFailed(_ failure: AccountDeletion.Failure) -> AlertState {
        AlertState {
            TextState("Something Went Wrong")
        } message: {
            switch failure {
            case .notDeleted:
                TextState("Your account couldn't be deleted.")
            case .notFullyDeleted:
                TextState("Your account couldn't be fully deleted.")
            case .notSignedOut:
                TextState("You couldn't be signed out.")
            }
        }
    }

    static let confirmAccountDeletion = AlertState {
        TextState("Delete Account")
    } actions: {
        ButtonState(role: .destructive, action: .confirmAccountDeletion) {
            TextState("Delete")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Your account and all your entries will be permanently deleted. Are you sure?")
    }

    static func confirmImport(_ entriesImport: EntriesArchive.Import) -> AlertState {
        let duplicateCount = entriesImport.duplicateCount
        let entries = entriesImport.entries
        let invalidCount = entriesImport.invalidCount
        let message: TextState? =
            switch (duplicateCount > 0, invalidCount > 0) {
            case (true, true):
                TextState(
                    "^[\(duplicateCount) entry](inflect: true) already in Lexicon and ^[\(invalidCount) entry](inflect: true) that can't be imported will be skipped."
                )
            case (true, false):
                TextState("^[\(duplicateCount) entry](inflect: true) already in Lexicon will be skipped.")
            case (false, true):
                TextState("^[\(invalidCount) entry](inflect: true) can't be imported and will be skipped.")
            case (false, false):
                nil
            }
        return AlertState(
            title: {
                TextState("Import ^[\(entries.count) Entry](inflect: true)?")
            },
            actions: {
                ButtonState(action: .confirmImport(entries)) {
                    TextState("Import")
                }
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                }
            },
            message: message.map { message in { message } }
        )
    }

    static let confirmSignOut = AlertState {
        TextState("Sign Out")
    } actions: {
        ButtonState(role: .destructive, action: .confirmSignOut) {
            TextState("Sign Out")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Are you sure you want to sign out?")
    }

    static func importFailed(_ error: any Error) -> AlertState {
        AlertState {
            TextState("Something Went Wrong")
        } message: {
            switch error {
            case FileClient.ReadError.tooLarge:
                TextState("This file is too large to import.")
            case EntriesArchive.ReadError.invalid:
                TextState("This file isn't a Lexicon export.")
            case EntriesArchive.ReadError.unsupportedVersion:
                TextState("This file was made by a newer version of Lexicon.")
            default:
                TextState("The file couldn't be opened.")
            }
        }
    }

    static let importHasNoEntries = AlertState {
        TextState("Nothing to Import")
    } message: {
        TextState("There are no entries to import.")
    }

    static let importHasOnlyDuplicates = AlertState {
        TextState("Nothing to Import")
    } message: {
        TextState("All the entries in this file are already in Lexicon.")
    }

    static let signOutFailed = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("You couldn't be signed out.")
    }
}

private let logger = Logger(category: "Settings")
