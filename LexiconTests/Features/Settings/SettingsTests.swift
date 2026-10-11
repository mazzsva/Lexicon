//
//  SettingsTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import AuthenticationServices
import ComposableArchitecture
import CustomDump
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct SettingsTests {
        // A sign out clears the local entries
        @Test
        func theSignOutButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.signOutButtonTapped) {
                $0.alert = .confirmSignOut
            }
        }

        // The app feature listens to Firebase, so the settings only start the sign out
        @Test
        func confirmingTheSignOutSignsTheUserOut() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmSignOut

            await confirmation("Signs the user out") { signsOut in
                let store = TestStore(initialState: state) {
                    Settings()
                } withDependencies: {
                    $0.authClient.signOut = { signsOut() }
                }

                await store.send(.alert(.presented(.confirmSignOut))) {
                    $0.alert = nil
                }
                await store.finish()
            }
        }

        // The settings stay on screen because the user is still signed in
        @Test
        func aFailedSignOutShowsAnAlert() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmSignOut

            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.signOut = { throw SignOutFailure() }
            }

            await store.send(.alert(.presented(.confirmSignOut))) {
                $0.alert = nil
            }
            await store.receive(\.signOutFailed) {
                $0.alert = .signOutFailed
            }
        }

        // A dismissed confirmation must not sign the user out
        @Test
        func dismissingTheAlertClearsIt() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmSignOut

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.alert(.dismiss)) {
                $0.alert = nil
            }
        }

        // The deletion removes the entries from every device
        @Test
        func theDeleteAccountButtonAsksForConfirmation() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.deleteAccountButtonTapped) {
                $0.alert = .confirmAccountDeletion
            }
        }

        // The account must exist until the entries and the Apple token are gone
        @Test
        func confirmingTheAccountDeletionWalksThroughEveryStep() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.deleteAccount = {}
                $0.authClient.reauthenticate = { credential in
                    expectNoDifference(credential, .mock)
                }
                $0.authClient.revokeAppleToken = { authorizationCode in
                    expectNoDifference(authorizationCode, AppleCredential.mock.authorizationCode)
                }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { uid in
                    expectNoDifference(uid, User.mock.uid)
                }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.deletionStep = .entriesDeleted
            }
            await store.receive(\.appleCredentialRevoked) {
                $0.deletionStep = .credentialRevoked
            }
            await store.finish()
        }

        // The deletion must not stop halfway
        @Test
        func theButtonsAreIgnoredWhileTheAccountIsBeingDeleted() async {
            var state = Settings.State(user: .mock)
            state.deletionStep = .deleting

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.deleteAccountButtonTapped)
            await store.send(.dismissButtonTapped)
            await store.send(.signOutButtonTapped)
        }

        // The user closed the Apple sheet, so the app returns to the settings
        @Test
        func aCanceledReauthorizationStopsTheDeletionSilently() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.signInWithAppleClient.requestCredential = { throw ASAuthorizationError(.canceled) }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.accountDeletionFailed) {
                $0.deletionStep = nil
            }
        }

        // Without the code the app cannot revoke the Apple token, so it deletes nothing
        @Test
        func aCredentialWithoutAnAuthorizationCodeFailsTheDeletion() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.signInWithAppleClient.requestCredential = {
                    AppleCredential(
                        authorizationCode: nil,
                        idToken: "mock-id-token",
                        isFirstAuthorization: false,
                        rawNonce: "mock-raw-nonce"
                    )
                }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.accountDeletionFailed) {
                $0.alert = .accountDeletionFailed
                $0.deletionStep = nil
            }
        }

        // The deletion needs a recent sign in, and Firebase decides whether the credential counts
        @Test
        func aFailedReauthenticationShowsAnAlert() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.reauthenticate = { _ in throw DeletionFailure() }
                $0.continuousClock = clock
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }
            await store.receive(\.accountDeletionFailed) {
                $0.alert = .accountDeletionFailed
                $0.deletionStep = nil
            }
            await store.finish()
        }

        // No entry is gone yet, so the alert must not report an unfinished deletion
        @Test
        func aFailureBeforeTheEntriesAreDeletedReportsAFailedDeletion() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.reauthenticate = { _ in }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in throw DeletionFailure() }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }
            await store.receive(\.accountDeletionFailed) {
                $0.alert = .accountDeletionFailed
                $0.deletionStep = nil
            }
            await store.finish()
        }

        // The entries are already gone, so the alert must not report a deletion that did not start
        @Test
        func aFailureAfterTheEntriesAreDeletedReportsAnUnfinishedDeletion() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.reauthenticate = { _ in }
                $0.authClient.revokeAppleToken = { _ in throw DeletionFailure() }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.deletionStep = .entriesDeleted
            }
            await store.receive(\.accountDeletionFailed) {
                $0.alert = .accountDeletionUnfinished
                $0.deletionStep = nil
            }
            await store.finish()
        }

        // Apple no longer trusts the app, so the session cannot continue
        @Test
        func aFailureAfterTheCredentialIsRevokedSignsTheUserOut() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            await confirmation("Signs the user out") { signsOut in
                let store = TestStore(initialState: state) {
                    Settings()
                } withDependencies: {
                    $0.authClient.deleteAccount = { throw DeletionFailure() }
                    $0.authClient.reauthenticate = { _ in }
                    $0.authClient.revokeAppleToken = { _ in }
                    $0.authClient.signOut = { signsOut() }
                    $0.continuousClock = clock
                    $0.entriesClient.deleteAll = { _ in }
                    $0.signInWithAppleClient.requestCredential = { .mock }
                }

                await store.send(.alert(.presented(.confirmAccountDeletion))) {
                    $0.alert = nil
                    $0.deletionStep = .reauthenticating
                }
                await store.receive(\.appleCredentialReceived) {
                    $0.deletionStep = .deleting
                }
                await store.receive(\.entriesDeleted) {
                    $0.deletionStep = .entriesDeleted
                }
                await store.receive(\.appleCredentialRevoked) {
                    $0.deletionStep = .credentialRevoked
                }
                await store.receive(\.accountDeletionFailed)
                await store.finish()
            }
        }

        // The user keeps a session that Apple no longer trusts, so the alert must say so
        @Test
        func aFailedSignOutAfterTheRevokeShowsAnAlert() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.deleteAccount = { throw DeletionFailure() }
                $0.authClient.reauthenticate = { _ in }
                $0.authClient.revokeAppleToken = { _ in }
                $0.authClient.signOut = { throw SignOutFailure() }
                $0.continuousClock = clock
                $0.entriesClient.deleteAll = { _ in }
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }
            await store.receive(\.entriesDeleted) {
                $0.deletionStep = .entriesDeleted
            }
            await store.receive(\.appleCredentialRevoked) {
                $0.deletionStep = .credentialRevoked
            }
            await store.receive(\.accountDeletionFailed)
            await store.receive(\.signOutFailed) {
                $0.alert = .signOutFailed
                $0.deletionStep = nil
            }
            await store.finish()
        }

        // A request that never returns leaves the user with a spinner
        @Test
        func aStalledDeletionTimesOutAfterOneMinute() async {
            var state = Settings.State(user: .mock)
            state.alert = .confirmAccountDeletion

            let clock = TestClock()
            let store = TestStore(initialState: state) {
                Settings()
            } withDependencies: {
                $0.authClient.reauthenticate = { _ in try await Task.never() }
                $0.continuousClock = clock
                $0.signInWithAppleClient.requestCredential = { .mock }
            }

            await store.send(.alert(.presented(.confirmAccountDeletion))) {
                $0.alert = nil
                $0.deletionStep = .reauthenticating
            }
            await store.receive(\.appleCredentialReceived) {
                $0.deletionStep = .deleting
            }

            await clock.advance(by: .seconds(60))
            await store.receive(\.accountDeletionFailed) {
                $0.alert = .accountDeletionFailed
                $0.deletionStep = nil
            }
            await store.finish()
        }

        // Home presents the settings, so only the dismiss effect can close them
        @Test
        func theDismissButtonClosesTheSettings() async {
            await confirmation("Dismisses the settings") { dismissesSettings in
                let store = TestStore(initialState: Settings.State(user: .mock)) {
                    Settings()
                } withDependencies: {
                    $0.dismiss = DismissEffect { dismissesSettings() }
                }

                await store.send(.dismissButtonTapped)
                await store.finish()
            }
        }

        #if DEBUG
        // The button fills an empty account in the debug builds
        @Test
        func theDebugAddMockEntriesButtonSavesTheMockEntries() async {
            let saved = LockIsolated<[Entry]>([])

            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            } withDependencies: {
                $0.entriesClient.save = { entry, uid in
                    expectNoDifference(uid, User.mock.uid)
                    saved.withValue { $0.append(entry) }
                }
            }

            await store.send(.debugAddMockEntriesButtonTapped)
            await store.finish()
            expectNoDifference(saved.value, Entry.mocks)
        }

        // The button clears the entries and keeps the account
        @Test
        func theDebugDeleteAllEntriesButtonDeletesEveryEntry() async {
            await confirmation("Deletes all the entries") { deletesAllEntries in
                let store = TestStore(initialState: Settings.State(user: .mock)) {
                    Settings()
                } withDependencies: {
                    $0.entriesClient.deleteAll = { uid in
                        expectNoDifference(uid, User.mock.uid)
                        deletesAllEntries()
                    }
                }

                await store.send(.debugDeleteAllEntriesButtonTapped)
                await store.finish()
            }
        }

        @Test
        func theDebugResetWelcomeToggleSetsTheFlagForTheNextLaunch() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            await store.send(.debugResetWelcomeToggleChanged(true)) {
                $0.$showsWelcomeAtNextLaunch.withLock { $0 = true }
            }
            await store.send(.debugResetWelcomeToggleChanged(false)) {
                $0.$showsWelcomeAtNextLaunch.withLock { $0 = false }
            }
        }
        #endif

        @Test
        func theImportButtonOpensTheFileImporter() async {
            let store = TestStore(
                initialState: Settings.State(entries: SharedReader(value: []), isEntriesSynced: true, user: .mock)
            ) {
                Settings()
            }

            await store.send(.importEntriesButtonTapped) {
                $0.isFileImporterPresented = true
            }
            await store.send(.fileImporterPresentationChanged(false)) {
                $0.isFileImporterPresented = false
            }
        }

        @Test
        func theImportButtonWaitsForTheFirstLoad() async {
            let store = TestStore(initialState: Settings.State(user: .mock)) {
                Settings()
            }

            #expect(!store.state.canExportEntries)
            #expect(!store.state.canImportEntries)
            await store.send(.importEntriesButtonTapped)
        }

        @Test
        func onlyAListWithEntriesCanBeExported() {
            #expect(!Settings.State(entries: SharedReader(value: []), user: .mock).canExportEntries)
            #expect(Settings.State(entries: SharedReader(value: [.blueMoon]), user: .mock).canExportEntries)
        }

        @Test
        func aPickedFileAsksToImportOnlyTheNewValidEntries() async {
            let now = Date(timeIntervalSince1970: 1_791_711_000)
            let file = Data(
                """
                {
                  "version": 1,
                  "entries": [
                    { "id": "\(Entry.blueMoon.id)", "term": "Once in a blue moon" },
                    {
                      "id": "\(UUID(5))",
                      "term": "  Break the ice  ",
                      "definition": "  To start a conversation.  ",
                      "isBookmarked": true,
                      "createdAt": "2025-06-15T15:06:40.000Z"
                    },
                    { "id": "\(UUID(5))", "term": "Break the ice again" },
                    { "term": "Spill the beans" },
                    { "term": "   " }
                  ]
                }
                """
                .utf8
            )
            let imported = [
                Entry(
                    createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                    definition: "To start a conversation.",
                    id: UUID(5),
                    isBookmarked: true,
                    term: "Break the ice"
                ),
                Entry(createdAt: now, definition: "", id: UUID(9), isBookmarked: false, term: "Spill the beans"),
            ]

            let store = TestStore(
                initialState: Settings.State(
                    entries: SharedReader(value: IdentifiedArray(uniqueElements: Entry.mocks)),
                    isEntriesSynced: true,
                    user: .mock
                )
            ) {
                Settings()
            } withDependencies: {
                $0.date.now = now
                $0.fileClient.read = { url, maximumSize in
                    expectNoDifference(url, URL(filePath: "/Entries.json"))
                    expectNoDifference(maximumSize, Settings.maximumImportFileSize)
                    return file
                }
                $0.uuid = .constant(UUID(9))
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .confirmImport(imported, duplicateCount: 1, invalidCount: 1)
            }
            await store.send(.alert(.presented(.confirmImport(imported)))) {
                $0.alert = nil
            }
            await store.receive(\.delegate.didImport, imported)
        }

        @Test
        func theImportButtonWaitsForTheEntriesToSync() async {
            let store = TestStore(initialState: Settings.State(entries: SharedReader(value: []), user: .mock)) {
                Settings()
            }

            await store.send(.importEntriesButtonTapped) {
                $0.alert = .importNeedsSync
            }
        }

        @Test
        func aConfirmationAfterTheSyncStopsDoesNotImport() async {
            var state = Settings.State(entries: SharedReader(value: []), user: .mock)
            state.alert = .confirmImport([.blueMoon], duplicateCount: 0, invalidCount: 0)

            let store = TestStore(initialState: state) {
                Settings()
            }

            await store.send(.alert(.presented(.confirmImport([.blueMoon])))) {
                $0.alert = .importNeedsSync
            }
        }

        @Test
        func aFileWithOnlyDuplicatesHasNothingToImport() async {
            let store = TestStore(
                initialState: Settings.State(
                    entries: SharedReader(value: IdentifiedArray(uniqueElements: Entry.mocks)),
                    isEntriesSynced: true,
                    user: .mock
                )
            ) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in try EntriesArchive.data(for: [.blueMoon]) }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .importHasOnlyDuplicates
            }
        }

        @Test
        func aFileWithoutValidEntriesHasNothingToImport() async {
            let store = TestStore(
                initialState: Settings.State(entries: SharedReader(value: []), isEntriesSynced: true, user: .mock)
            ) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in Data(#"{ "version": 1, "entries": [{ "term": "" }] }"#.utf8) }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .importHasNoEntries
            }
        }

        @Test
        func aFileThatFailsToLoadShowsAnAlert() async {
            let store = TestStore(initialState: Settings.State(entries: SharedReader(value: []), user: .mock)) {
                Settings()
            } withDependencies: {
                $0.fileClient.read = { _, _ in throw FileClient.ReadError.tooLarge }
            }

            await store.send(.importFilePicked(.success(URL(filePath: "/Entries.json"))))
            await store.receive(\.importFileLoaded) {
                $0.alert = .importFailed(FileClient.ReadError.tooLarge)
            }
        }

        @Test
        func aFailedPickShowsAnAlert() async {
            let store = TestStore(initialState: Settings.State(entries: SharedReader(value: []), user: .mock)) {
                Settings()
            }

            await store.send(.importFilePicked(.failure(CocoaError(.fileReadNoPermission)))) {
                $0.alert = .importFailed(CocoaError(.fileReadNoPermission))
            }
        }

        @Test(
            arguments: [
                (FileClient.ReadError.tooLarge as any Error, "This file is too large to import."),
                (EntriesArchive.Error.invalid, "This file isn't a Lexicon export."),
                (EntriesArchive.Error.unsupportedVersion, "This file was made by a newer version of Lexicon."),
                (CocoaError(.fileReadNoPermission), "The file couldn't be opened."),
            ]
        )
        func eachImportFailureHasItsOwnMessage(error: any Error, message: String) {
            expectNoDifference(AlertState<Settings.Alert>.importFailed(error).message, TextState(message))
        }

        @Test
        func theConfirmationListsTheSkippedEntries() {
            expectNoDifference(
                AlertState<Settings.Alert>.confirmImport([.blueMoon], duplicateCount: 0, invalidCount: 0).message,
                nil
            )
            expectNoDifference(
                AlertState<Settings.Alert>.confirmImport([.blueMoon], duplicateCount: 2, invalidCount: 0).message,
                TextState("^[\(2) entry](inflect: true) already in Lexicon will be skipped.")
            )
            expectNoDifference(
                AlertState<Settings.Alert>.confirmImport([.blueMoon], duplicateCount: 0, invalidCount: 1).message,
                TextState("^[\(1) entry](inflect: true) can't be imported and will be skipped.")
            )
        }

        private struct DeletionFailure: Error {}

        private struct SignOutFailure: Error {}
    }
}
