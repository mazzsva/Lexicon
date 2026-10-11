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
    enum AccountDeletionError: Error {
        case missingAuthorizationCode
        case timedOut
    }

    enum Alert: Equatable {
        case confirmAccountDeletion
        case confirmImport([Entry])
        case confirmSignOut
    }

    enum DeletionStep: Equatable {
        case credentialRevoked
        case deleting
        case entriesDeleted
        case reauthenticating
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Settings.Alert>?
        var deletionStep: DeletionStep?
        @SharedReader var entries: IdentifiedArrayOf<Entry>?
        var isEntriesSynced: Bool
        var isFileImporterPresented = false
        #if DEBUG
        @Shared(.showsWelcomeAtNextLaunch) var showsWelcomeAtNextLaunch
        #endif
        let user: User

        init(
            entries: SharedReader<IdentifiedArrayOf<Entry>?> = SharedReader(value: nil),
            isEntriesSynced: Bool = false,
            user: User
        ) {
            _entries = entries
            self.isEntriesSynced = isEntriesSynced
            self.user = user
        }

        var canExportEntries: Bool { !(entries?.isEmpty ?? true) }

        var canImportEntries: Bool { entries != nil }

        var isDeletingAccount: Bool { deletionStep != nil }

        var isReauthenticating: Bool { deletionStep == .reauthenticating }
    }

    enum Action {
        case accountDeletionFailed(any Error)
        case alert(PresentationAction<Alert>)
        case appleCredentialReceived
        case appleCredentialRevoked
        #if DEBUG
        case debugAddMockEntriesButtonTapped
        case debugDeleteAllEntriesButtonTapped
        case debugResetWelcomeToggleChanged(Bool)
        #endif
        case delegate(Delegate)
        case deleteAccountButtonTapped
        case dismissButtonTapped
        case entriesDeleted
        case fileImporterPresentationChanged(Bool)
        case importEntriesButtonTapped
        case importFileLoaded(Result<[EntriesArchive.Record], any Error>)
        case importFilePicked(Result<URL, any Error>)
        case signOutButtonTapped
        case signOutFailed(any Error)

        @CasePathable
        enum Delegate {
            case didImport([Entry])
        }
    }

    enum CancelID {
        case importFileLoad
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.fileClient) var fileClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .accountDeletionFailed(let error):
                guard state.deletionStep != .credentialRevoked else {
                    logger.error(
                        "Account deletion failed after the revoke attempt; signing out: \(error, privacy: .public)")
                    return signOut()
                }
                let hasDeletedEntries = state.deletionStep == .entriesDeleted
                state.deletionStep = nil
                if !error.isSignInWithAppleCancellation {
                    logger.error("Account deletion failed: \(error, privacy: .public)")
                    state.alert = hasDeletedEntries ? .accountDeletionUnfinished : .accountDeletionFailed
                }
                return .none

            case .alert(.presented(.confirmAccountDeletion)):
                state.deletionStep = .reauthenticating
                return .merge(
                    .cancel(id: CancelID.importFileLoad),
                    deleteAccount(uid: state.user.uid)
                )

            case .alert(.presented(.confirmImport(let entries))):
                guard !state.isDeletingAccount else { return .none }
                guard state.isEntriesSynced else {
                    state.alert = .importNeedsSync
                    return .none
                }
                return .send(.delegate(.didImport(entries)))

            case .alert(.presented(.confirmSignOut)):
                return .merge(
                    .cancel(id: CancelID.importFileLoad),
                    signOut()
                )

            case .alert:
                return .none

            case .appleCredentialReceived:
                state.deletionStep = .deleting
                return .none

            case .appleCredentialRevoked:
                state.deletionStep = .credentialRevoked
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
                guard !state.isDeletingAccount else { return .none }
                state.alert = .confirmAccountDeletion
                return .none

            case .dismissButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                return .run { _ in await dismiss() }

            case .entriesDeleted:
                state.deletionStep = .entriesDeleted
                return .none

            case .fileImporterPresentationChanged(let isPresented):
                state.isFileImporterPresented = isPresented
                return .none

            case .importEntriesButtonTapped:
                guard state.canImportEntries, !state.isDeletingAccount else { return .none }
                guard state.isEntriesSynced else {
                    state.alert = .importNeedsSync
                    return .none
                }
                state.isFileImporterPresented = true
                return .none

            case .importFileLoaded(.failure(let error)):
                logger.error("Loading the import file failed: \(error, privacy: .public)")
                guard !state.isDeletingAccount else { return .none }
                state.alert = .importFailed(error)
                return .none

            case .importFileLoaded(.success(let records)):
                guard !state.isDeletingAccount, let existing = state.entries else { return .none }
                guard state.isEntriesSynced else {
                    state.alert = .importNeedsSync
                    return .none
                }
                state.alert = importAlert(for: records, existing: existing)
                return .none

            case .importFilePicked(.failure(let error)):
                logger.error("Picking the import file failed: \(error, privacy: .public)")
                state.alert = .importFailed(error)
                return .none

            case .importFilePicked(.success(let url)):
                guard !state.isDeletingAccount else { return .none }
                return loadImportFile(url)

            case .signOutButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                state.alert = .confirmSignOut
                return .none

            case .signOutFailed(let error):
                state.deletionStep = nil
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

    private func deleteAccount(uid: String) -> Effect<Action> {
        .run { send in
            let credential = try await signInWithAppleClient.requestCredential()
            guard let authorizationCode = credential.authorizationCode else {
                throw AccountDeletionError.missingAuthorizationCode
            }
            await send(.appleCredentialReceived)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await clock.sleep(for: .seconds(60))
                    throw AccountDeletionError.timedOut
                }
                group.addTask {
                    try await authClient.reauthenticate(credential: credential)
                    try Task.checkCancellation()
                    try await entriesClient.deleteAll(uid: uid)
                    await send(.entriesDeleted)
                    try Task.checkCancellation()
                    try await authClient.revokeAppleToken(authorizationCode: authorizationCode)
                    await send(.appleCredentialRevoked)
                    try Task.checkCancellation()
                    try await authClient.deleteAccount()
                }
                try await group.next()
                group.cancelAll()
            }
        } catch: { error, send in
            await send(.accountDeletionFailed(error))
        }
    }

    private func importAlert(
        for records: [EntriesArchive.Record],
        existing: IdentifiedArrayOf<Entry>
    ) -> AlertState<Alert> {
        var duplicateCount = 0
        var entries = IdentifiedArrayOf<Entry>()
        var invalidCount = 0
        for record in records {
            guard let content = try? Entry.Content(term: record.term ?? "", definition: record.definition ?? "")
            else {
                invalidCount += 1
                continue
            }
            let id = record.id ?? uuid()
            guard existing[id: id] == nil else {
                duplicateCount += 1
                continue
            }
            guard entries[id: id] == nil else { continue }
            guard
                let entry = try? Entry(
                    content: content,
                    createdAt: record.createdAt ?? now,
                    id: id,
                    isBookmarked: record.isBookmarked ?? false
                )
            else {
                invalidCount += 1
                continue
            }
            entries.append(entry)
        }
        guard !entries.isEmpty else {
            return duplicateCount > 0 ? .importHasOnlyDuplicates : .importHasNoEntries
        }
        return .confirmImport(Array(entries), duplicateCount: duplicateCount, invalidCount: invalidCount)
    }

    private func loadImportFile(_ url: URL) -> Effect<Action> {
        .run { send in
            do {
                let data = try await fileClient.read(url: url, maximumSize: EntriesArchive.maximumFileSize)
                await send(.importFileLoaded(.success(try EntriesArchive.records(from: data))))
            } catch {
                await send(.importFileLoaded(.failure(error)))
            }
        }
        .cancellable(id: CancelID.importFileLoad, cancelInFlight: true)
    }

    private func signOut() -> Effect<Action> {
        .run { _ in
            try await authClient.signOut()
        } catch: { error, send in
            await send(.signOutFailed(error))
        }
    }
}

extension AlertState where Action == Settings.Alert {
    static let accountDeletionFailed = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("Your account couldn't be deleted.")
    }

    static let accountDeletionUnfinished = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("Your account couldn't be fully deleted.")
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

    static func confirmImport(_ entries: [Entry], duplicateCount: Int, invalidCount: Int) -> AlertState {
        let duplicates = TextState("^[\(duplicateCount) entry](inflect: true) already in Lexicon will be skipped.")
        let invalid = TextState("^[\(invalidCount) entry](inflect: true) can't be imported and will be skipped.")
        let message: TextState? =
            switch (duplicateCount > 0, invalidCount > 0) {
            case (true, true): duplicates + TextState(verbatim: " ") + invalid
            case (true, false): duplicates
            case (false, true): invalid
            case (false, false): nil
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

    static let importNeedsSync = AlertState {
        TextState("Can't Import Right Now")
    } message: {
        TextState("Connect to the internet and wait for your entries to sync, then try again.")
    }

    static let signOutFailed = AlertState {
        TextState("Something Went Wrong")
    } message: {
        TextState("You couldn't be signed out.")
    }
}

private let logger = Logger(category: "Settings")
