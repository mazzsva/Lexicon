//
//  EntryFormTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    @MainActor
    struct EntryFormTests {
        // An entry needs a term, and the definition can stay empty
        @Test
        func onlyANonBlankTermIsSubmittable() {
            var state = EntryForm.State()
            #expect(state.isCreating)
            #expect(!state.isSubmittable)

            state.term = "   \n  "
            #expect(!state.isSubmittable)

            state.term = "Burn the candle at both ends"
            #expect(state.isSubmittable)
        }

        // The form gives the entry an identity, so the save does not wait for the server
        @Test
        func creatingAnEntryGeneratesItsIdentityAndDate() async throws {
            let now = Date(timeIntervalSince1970: 1_751_000_000)
            let created = try Entry(
                createdAt: now,
                definition: "The easiest wins, taken first.",
                id: UUID(0),
                isBookmarked: false,
                term: "Low-hanging fruit"
            )

            let store = TestStore(initialState: EntryForm.State()) {
                EntryForm()
            } withDependencies: {
                $0.date.now = now
                $0.uuid = .incrementing
            }

            await store.send(.binding(.set(\.term, "  Low-hanging fruit  "))) {
                $0.term = "  Low-hanging fruit  "
            }
            await store.send(.binding(.set(\.definition, created.definition))) {
                $0.definition = created.definition
            }
            await store.send(.saveButtonTapped)
            await store.receive(\.delegate.didCreate, created)
        }

        // The identity and the date come from the original, so the save replaces it
        @Test
        func editingAnEntryKeepsItsIdentity() async throws {
            let edited = try Entry(
                createdAt: Entry.blueMoon.createdAt,
                definition: "A rare event.",
                id: Entry.blueMoon.id,
                isBookmarked: Entry.blueMoon.isBookmarked,
                term: Entry.blueMoon.term
            )

            let store = TestStore(initialState: EntryForm.State(entry: .blueMoon)) {
                EntryForm()
            }

            await store.send(.binding(.set(\.definition, "  A rare event.  "))) {
                $0.definition = "  A rare event.  "
            }
            await store.send(.saveButtonTapped)
            await store.receive(\.delegate.didUpdate, edited)
        }

        // The view disables the save button, and the reducer refuses the term as well
        @Test
        func savingABlankTermDoesNothing() async {
            let store = TestStore(initialState: EntryForm.State()) {
                EntryForm()
            }

            await store.send(.binding(.set(\.term, "   "))) {
                $0.term = "   "
            }
            await store.send(.saveButtonTapped)
        }

        @Test
        func savingAnEntryOverTheSizeLimitDoesNothing() async {
            let term = String(repeating: "a", count: Entry.Content.maximumSize / 2)
            let definition = String(repeating: "é", count: Entry.Content.maximumSize / 4 + 1)

            let store = TestStore(initialState: EntryForm.State()) {
                EntryForm()
            }

            await store.send(.binding(.set(\.term, term))) {
                $0.term = term
            }
            await store.send(.binding(.set(\.definition, definition))) {
                $0.definition = definition
            }
            #expect(!store.state.isSubmittable)

            await store.send(.saveButtonTapped)
        }

        // The parent presents the form, so only the dismiss effect can close it
        @Test
        func theDismissButtonClosesTheForm() async {
            await confirmation("Dismisses the form") { dismissesForm in
                let store = TestStore(initialState: EntryForm.State(entry: .blueMoon)) {
                    EntryForm()
                } withDependencies: {
                    $0.dismiss = DismissEffect { dismissesForm() }
                }

                await store.send(.dismissButtonTapped)
                await store.finish()
            }
        }

        @Test
        func theTaskPrewarmsAnAvailableModel() async {
            await confirmation("Prewarms the model") { prewarms in
                let store = Self.store(EntryForm.State()) {
                    $0.definitionClient.isAvailable = { true }
                    $0.definitionClient.prewarm = { prewarms() }
                }

                await store.send(.task) {
                    $0.isModelAvailable = true
                }
                await store.finish()
            }
        }

        @Test
        func theTaskDoesNotPrewarmAnUnavailableModel() async {
            let store = Self.store(EntryForm.State()) {
                $0.definitionClient.isAvailable = { false }
            }

            await store.send(.task)
        }

        @Test
        func aGeneratedDefinitionStreamsIntoTheFieldAndSaves() async throws {
            let now = Date(timeIntervalSince1970: 1_751_000_000)
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            let created = try Entry(
                createdAt: now,
                definition: "Something that happens very rarely.",
                id: UUID(0),
                isBookmarked: false,
                term: "Once in a blue moon"
            )

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = Self.store(Self.generatableState(term: " Once in a blue moon ")) {
                    $0.date.now = now
                    $0.definitionClient.definition = { term, entry in
                        expectNoDifference(term, "Once in a blue moon")
                        expectNoDifference(entry, nil)
                        return definitions
                    }
                    $0.dictionaryClient.entry = { term in
                        expectNoDifference(term, "Once in a blue moon")
                        return nil
                    }
                    $0.hapticsClient.success = { playsHaptic() }
                    $0.uuid = .incrementing
                }

                await store.send(.generateDefinitionButtonTapped) {
                    $0.generation = .lookingUp(previousDefinition: "", term: "Once in a blue moon")
                }
                #expect(!store.state.isSubmittable)
                await store.receive(\.dictionaryEntryResponse, nil) {
                    $0.generation = .writing(previousDefinition: "")
                }

                continuation.yield("Something that")
                await store.receive(\.definitionGenerated, "Something that") {
                    $0.definition = "Something that"
                }
                continuation.yield(created.definition)
                await store.receive(\.definitionGenerated, created.definition) {
                    $0.definition = created.definition
                }
                continuation.finish()
                await store.receive(\.definitionGenerationFinished) {
                    $0.completedGenerationCount = 1
                    $0.generatedDefinition = EntryForm.GeneratedDefinition(text: created.definition)
                    $0.generation = nil
                }
                expectNoDifference(store.state.note, .generated(correctForm: nil))

                await store.send(.saveButtonTapped)
                await store.receive(\.delegate.didCreate, created)
                await store.finish()
            }
        }

        @Test
        func theModelReadsTheDictionaryEntryAndTheNoteNamesTheCorrectForm() async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            let entry = DictionaryEntry(
                correctForm: "nip in the bud",
                senses: ["To stop something at an early stage."],
                title: "nip it in the butt"
            )

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = Self.store(Self.generatableState(term: "nip it in the butt")) {
                    $0.definitionClient.definition = { _, received in
                        expectNoDifference(received, entry)
                        return definitions
                    }
                    $0.dictionaryClient.entry = { _ in entry }
                    $0.hapticsClient.success = { playsHaptic() }
                }

                await store.send(.generateDefinitionButtonTapped) {
                    $0.generation = .lookingUp(previousDefinition: "", term: "nip it in the butt")
                }
                await store.receive(\.dictionaryEntryResponse, entry) {
                    $0.generation = .writing(previousDefinition: "")
                }
                continuation.yield("To stop a problem early.")
                await store.receive(\.definitionGenerated, "To stop a problem early.") {
                    $0.definition = "To stop a problem early."
                }
                continuation.finish()
                await store.receive(\.definitionGenerationFinished, "nip in the bud") {
                    $0.completedGenerationCount = 1
                    $0.generatedDefinition = EntryForm.GeneratedDefinition(
                        correctForm: "nip in the bud",
                        text: "To stop a problem early."
                    )
                    $0.generation = nil
                }
                expectNoDifference(store.state.note, .generated(correctForm: "nip in the bud"))
                await store.finish()
            }
        }

        @Test
        func correctingTheTermRemovesTheCorrectForm() async {
            var state = Self.generatableState(term: "nip it in the butt")
            state.definition = "To stop a problem early."
            state.generatedDefinition = EntryForm.GeneratedDefinition(
                correctForm: "nip in the bud",
                text: "To stop a problem early."
            )
            let store = Self.store(state)

            await store.send(.binding(.set(\.term, "nip in the bud"))) {
                $0.generatedDefinition?.correctForm = nil
                $0.term = "nip in the bud"
            }
            expectNoDifference(store.state.note, .generated(correctForm: nil))
        }

        @Test
        func generatingOverAWrittenDefinitionAsksAndThenReplacesIt() async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            var state = Self.generatableState(term: "Once in a blue moon")
            state.definition = "A rare event."

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = Self.store(state) {
                    $0.definitionClient.definition = { _, _ in definitions }
                    $0.hapticsClient.success = { playsHaptic() }
                }

                await store.send(.generateDefinitionButtonTapped) {
                    $0.confirmationDialog = .confirmReplacement
                }
                await store.send(.confirmationDialog(.presented(.confirmReplacement))) {
                    $0.confirmationDialog = nil
                    $0.definition = ""
                    $0.generation = .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon")
                }
                await store.receive(\.dictionaryEntryResponse, nil) {
                    $0.generation = .writing(previousDefinition: "A rare event.")
                }
                continuation.yield("Something that happens very rarely.")
                await store.receive(\.definitionGenerated, "Something that happens very rarely.") {
                    $0.definition = "Something that happens very rarely."
                }
                continuation.finish()
                await store.receive(\.definitionGenerationFinished) {
                    $0.completedGenerationCount = 1
                    $0.generatedDefinition = EntryForm.GeneratedDefinition(text: "Something that happens very rarely.")
                    $0.generation = nil
                }
                await store.finish()
            }
        }

        @Test
        func regeneratingTheSameDefinitionCountsAnotherCompletedGeneration() async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            var state = Self.generatedState()
            state.completedGenerationCount = 1

            await confirmation("Plays the success haptic") { playsHaptic in
                let store = Self.store(state) {
                    $0.definitionClient.definition = { _, _ in definitions }
                    $0.hapticsClient.success = { playsHaptic() }
                }

                await store.send(.generateDefinitionButtonTapped) {
                    $0.definition = ""
                    $0.generation = .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon")
                }
                await store.receive(\.dictionaryEntryResponse, nil) {
                    $0.generation = .writing(previousDefinition: "A rare event.")
                }
                continuation.yield("A rare event.")
                await store.receive(\.definitionGenerated, "A rare event.") {
                    $0.definition = "A rare event."
                }
                continuation.finish()
                await store.receive(\.definitionGenerationFinished) {
                    $0.completedGenerationCount = 2
                    $0.generation = nil
                }
                expectNoDifference(store.state.note, .generated(correctForm: nil))
                await store.finish()
            }
        }

        @Test
        func generatingOverAnEditedGeneratedDefinitionAsks() async {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.definition = "Something that happens very rarely, almost never."
            state.generatedDefinition = EntryForm.GeneratedDefinition(text: "Something that happens very rarely.")
            let store = Self.store(state)

            await store.send(.generateDefinitionButtonTapped) {
                $0.confirmationDialog = .confirmReplacement
            }
        }

        @Test
        func generatingOverABlankDefinitionDoesNotAsk() async {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.definition = "  \n "
            let store = Self.store(state) {
                $0.dictionaryClient.entry = { _ in
                    try await Task.never()
                    return nil
                }
            }

            await store.send(.generateDefinitionButtonTapped) {
                $0.definition = ""
                $0.generation = .lookingUp(previousDefinition: "  \n ", term: "Once in a blue moon")
            }
            await store.send(.stopGeneratingButtonTapped) {
                $0.definition = "  \n "
                $0.generation = nil
            }
        }

        @Test
        func cancelingTheReplacementKeepsTheWrittenDefinition() async {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.definition = "A rare event."
            let store = Self.store(state)

            await store.send(.generateDefinitionButtonTapped) {
                $0.confirmationDialog = .confirmReplacement
            }
            await store.send(.confirmationDialog(.dismiss)) {
                $0.confirmationDialog = nil
            }
        }

        @Test
        func stoppingRestoresTheDefinitionAndIgnoresLateOutput() async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            let store = Self.store(Self.generatedState()) {
                $0.definitionClient.definition = { _, _ in definitions }
            }

            await store.send(.generateDefinitionButtonTapped) {
                $0.definition = ""
                $0.generation = .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon")
            }
            await store.receive(\.dictionaryEntryResponse, nil) {
                $0.generation = .writing(previousDefinition: "A rare event.")
            }
            continuation.yield("Something")
            await store.receive(\.definitionGenerated, "Something") {
                $0.definition = "Something"
            }
            await store.send(.stopGeneratingButtonTapped) {
                $0.definition = "A rare event."
                $0.generation = nil
            }
            expectNoDifference(store.state.note, .generated(correctForm: nil))
            continuation.yield("Something late")
            continuation.finish()
            await store.finish()
        }

        @Test
        func stoppingTheLookupRestoresTheDefinition() async {
            let store = Self.store(Self.generatedState()) {
                $0.dictionaryClient.entry = { _ in
                    try await Task.never()
                    return nil
                }
            }

            await store.send(.generateDefinitionButtonTapped) {
                $0.definition = ""
                $0.generation = .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon")
            }
            await store.send(.stopGeneratingButtonTapped) {
                $0.definition = "A rare event."
                $0.generation = nil
            }
            expectNoDifference(store.state.note, .generated(correctForm: nil))
        }

        @Test(
            arguments: [
                nil, EntryForm.Generation.failed(.failed), .writing(previousDefinition: "A rare event."),
            ]
        )
        func aLookupResponseOutsideTheLookupDoesNotStartTheModel(generation: EntryForm.Generation?) async {
            var state = Self.generatedState()
            state.generation = generation
            let store = Self.store(state)

            await store.send(.dictionaryEntryResponse(nil))
        }

        @Test(
            arguments: [
                nil, EntryForm.Generation.failed(.failed),
                .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon"),
            ]
        )
        func modelOutputOutsideTheWritingDoesNothing(generation: EntryForm.Generation?) async {
            var state = Self.generatedState()
            state.generation = generation
            let store = Self.store(state)

            await store.send(.definitionGenerated("Something late"))
            await store.send(.definitionGenerationFinished(correctForm: nil))
            await store.send(.definitionGenerationFailed(DefinitionClient.GenerationError.failed))
        }

        @Test(
            arguments: [
                DefinitionClient.GenerationError.failed, .unknownTerm, .unsupportedLanguage, .unsupportedTerm,
            ]
        )
        func aFailedGenerationRestoresTheDefinitionAndExplains(error: DefinitionClient.GenerationError) async {
            await Self.expectFailure(error, after: error)
        }

        @Test
        func anUnexpectedErrorIsAFailedGeneration() async {
            struct ModelError: Error {}
            await Self.expectFailure(.failed, after: ModelError())
        }

        @Test(arguments: [nil, "  \n "])
        func aGenerationWithABlankDefinitionFails(definition: String?) async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()

            await confirmation("Plays the warning haptic") { playsHaptic in
                let store = Self.store(Self.generatedState()) {
                    $0.definitionClient.definition = { _, _ in definitions }
                    $0.hapticsClient.warning = { playsHaptic() }
                }

                await store.send(.generateDefinitionButtonTapped) {
                    $0.definition = ""
                    $0.generation = .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon")
                }
                await store.receive(\.dictionaryEntryResponse, nil) {
                    $0.generation = .writing(previousDefinition: "A rare event.")
                }
                if let definition {
                    continuation.yield(definition)
                    await store.receive(\.definitionGenerated, definition) {
                        $0.definition = definition
                    }
                }
                continuation.finish()
                await store.receive(\.definitionGenerationFinished) {
                    $0.definition = "A rare event."
                    $0.generation = .failed(.failed)
                }
                expectNoDifference(store.state.note, .failure(.failed))
                await store.finish()
            }
        }

        @Test
        func generatingAgainClearsTheFailure() async {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.generation = .failed(.failed)
            let store = Self.store(state) {
                $0.dictionaryClient.entry = { _ in
                    try await Task.never()
                    return nil
                }
            }

            await store.send(.generateDefinitionButtonTapped) {
                $0.generation = .lookingUp(previousDefinition: "", term: "Once in a blue moon")
            }
            await store.send(.stopGeneratingButtonTapped) {
                $0.generation = nil
            }
        }

        @Test
        func editingTheTermClearsTheFailure() async {
            var state = Self.generatableState(term: "once in a blu mon")
            state.generation = .failed(.unknownTerm)
            let store = Self.store(state)

            await store.send(.binding(.set(\.term, "once in a blue moon"))) {
                $0.generation = nil
                $0.term = "once in a blue moon"
            }
        }

        @Test
        func writingTheDefinitionClearsTheFailure() async {
            var state = Self.generatableState(term: "once in a blu mon")
            state.generation = .failed(.unknownTerm)
            let store = Self.store(state)

            await store.send(.binding(.set(\.definition, "Very rarely."))) {
                $0.definition = "Very rarely."
                $0.generation = nil
            }
        }

        @Test
        func theNoteShowsAFailureBeforeTheGeneratedDefinition() {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.definition = "Very rarely."
            state.generatedDefinition = EntryForm.GeneratedDefinition(text: "Very rarely.")
            expectNoDifference(state.note, .generated(correctForm: nil))

            state.generation = .failed(.unknownTerm)
            expectNoDifference(state.note, .failure(.unknownTerm))

            state.generation = nil
            state.definition = "Very rarely, almost never."
            expectNoDifference(state.note, nil)
        }

        @Test(arguments: ["", "  \n ", String(repeating: "a", count: EntryForm.maximumGeneratableTermLength + 1)])
        func onlyAShortNonBlankTermCanBeGenerated(term: String) async {
            let store = Self.store(Self.generatableState(term: term))

            #expect(!store.state.isGenerateButtonEnabled)
            await store.send(.generateDefinitionButtonTapped)
        }

        @Test
        func aTermThatIsTooLongExplainsWhyItCannotBeGenerated() {
            var state = Self.generatableState(
                term: String(repeating: "a", count: EntryForm.maximumGeneratableTermLength + 1)
            )
            expectNoDifference(state.note, .termTooLong)

            state.definition = "  \n "
            expectNoDifference(state.note, .termTooLong)

            state.definition = "Very rarely."
            expectNoDifference(state.note, nil)

            state.definition = ""
            state.isModelAvailable = false
            expectNoDifference(state.note, nil)
        }

        @Test
        func aTermThatIsTooLongKeepsTheGeneratedNote() {
            var state = Self.generatedState()
            expectNoDifference(state.note, .generated(correctForm: nil))

            state.term = String(repeating: "a", count: EntryForm.maximumGeneratableTermLength + 1)
            #expect(state.isTermTooLong)
            expectNoDifference(state.note, .generated(correctForm: nil))
        }

        @Test(
            arguments: [
                String(repeating: "a", count: EntryForm.maximumGeneratableTermLength),
                " \n" + String(repeating: "a", count: EntryForm.maximumGeneratableTermLength) + "  ",
            ]
        )
        func theLongestAllowedTermCanBeGenerated(term: String) {
            let state = Self.generatableState(term: term)

            #expect(state.isGenerateButtonEnabled)
            #expect(!state.isTermTooLong)
            expectNoDifference(state.note, nil)
        }

        @Test
        func aSlowLookupFallsBackToTheModel() async {
            let clock = TestClock()
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            let store = Self.store(Self.generatableState(term: "Once in a blue moon")) {
                $0.continuousClock = clock
                $0.definitionClient.definition = { _, entry in
                    expectNoDifference(entry, nil)
                    return definitions
                }
                $0.dictionaryClient.entry = { _ in
                    try await Task.never()
                    return nil
                }
            }

            await store.send(.generateDefinitionButtonTapped) {
                $0.generation = .lookingUp(previousDefinition: "", term: "Once in a blue moon")
            }
            await clock.advance(by: EntryForm.lookupTimeout)
            await store.receive(\.dictionaryEntryResponse, nil) {
                $0.generation = .writing(previousDefinition: "")
            }
            continuation.yield("Very rarely.")
            await store.receive(\.definitionGenerated, "Very rarely.") {
                $0.definition = "Very rarely."
            }
            await store.send(.stopGeneratingButtonTapped) {
                $0.definition = ""
                $0.generation = nil
            }
        }

        @Test
        func aFailedLookupFallsBackToTheModel() async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            let store = Self.store(Self.generatableState(term: "Once in a blue moon")) {
                $0.definitionClient.definition = { _, entry in
                    expectNoDifference(entry, nil)
                    return definitions
                }
                $0.dictionaryClient.entry = { _ in throw URLError(.notConnectedToInternet) }
            }

            await store.send(.generateDefinitionButtonTapped) {
                $0.generation = .lookingUp(previousDefinition: "", term: "Once in a blue moon")
            }
            await store.receive(\.dictionaryEntryResponse, nil) {
                $0.generation = .writing(previousDefinition: "")
            }
            continuation.yield("Very rarely.")
            await store.receive(\.definitionGenerated, "Very rarely.") {
                $0.definition = "Very rarely."
            }
            await store.send(.stopGeneratingButtonTapped) {
                $0.definition = ""
                $0.generation = nil
            }
        }

        @Test
        func anUnavailableModelCannotGenerate() async {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.isModelAvailable = false
            let store = Self.store(state)

            #expect(!store.state.isGenerateButtonEnabled)
            await store.send(.generateDefinitionButtonTapped)
        }

        @Test
        func savingWhileGeneratingDoesNothing() async {
            var state = Self.generatableState(term: "Once in a blue moon")
            state.generation = .writing(previousDefinition: "")
            let store = Self.store(state)

            await store.send(.saveButtonTapped)
        }

        private static func expectFailure(_ failure: DefinitionClient.GenerationError, after error: any Error) async {
            let (definitions, continuation) = AsyncThrowingStream<String, any Error>.makeStream()

            await confirmation("Plays the warning haptic") { playsHaptic in
                let store = Self.store(Self.generatedState()) {
                    $0.definitionClient.definition = { _, _ in definitions }
                    $0.hapticsClient.warning = { playsHaptic() }
                }

                await store.send(.generateDefinitionButtonTapped) {
                    $0.definition = ""
                    $0.generation = .lookingUp(previousDefinition: "A rare event.", term: "Once in a blue moon")
                }
                await store.receive(\.dictionaryEntryResponse, nil) {
                    $0.generation = .writing(previousDefinition: "A rare event.")
                }
                continuation.yield("Something")
                await store.receive(\.definitionGenerated, "Something") {
                    $0.definition = "Something"
                }
                continuation.finish(throwing: error)
                await store.receive(\.definitionGenerationFailed) {
                    $0.definition = "A rare event."
                    $0.generation = .failed(failure)
                }
                expectNoDifference(store.state.note, .failure(failure))
                await store.finish()
            }
        }

        private static func generatableState(term: String) -> EntryForm.State {
            var state = EntryForm.State()
            state.isModelAvailable = true
            state.term = term
            return state
        }

        private static func generatedState() -> EntryForm.State {
            var state = generatableState(term: "Once in a blue moon")
            state.definition = "A rare event."
            state.generatedDefinition = EntryForm.GeneratedDefinition(text: "A rare event.")
            return state
        }

        private static func store(
            _ state: EntryForm.State,
            dependencies: @escaping (inout DependencyValues) -> Void = { _ in }
        ) -> TestStoreOf<EntryForm> {
            TestStore(initialState: state) {
                EntryForm()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.dictionaryClient.entry = { _ in nil }
                dependencies(&$0)
            }
        }
    }
}
