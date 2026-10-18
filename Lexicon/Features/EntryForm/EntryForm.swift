//
//  EntryForm.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 20/07/26.
//

import ComposableArchitecture
import Foundation
import os

@Reducer
struct EntryForm {
    enum ConfirmationDialog: Equatable {
        case confirmReplacement
    }

    struct GeneratedDefinition: Equatable {
        var correctForm: String?
        let text: String
    }

    @CasePathable
    enum Generation: Equatable {
        case failed(DefinitionClient.GenerationError)
        case lookingUp(previousDefinition: String, term: String)
        case writing(previousDefinition: String)
    }

    enum Note: Hashable {
        case failure(DefinitionClient.GenerationError)
        case generated(correctForm: String?)
        case termTooLong
    }

    @ObservableState
    struct State: Equatable {
        var completedGenerationCount = 0
        @Presents var confirmationDialog: ConfirmationDialogState<ConfirmationDialog>?
        var definition: String
        let entry: Entry?
        var generatedDefinition: GeneratedDefinition?
        var generation: Generation?
        var isModelAvailable = false
        var term: String

        init(entry: Entry? = nil) {
            self.entry = entry
            definition = entry?.definition ?? ""
            term = entry?.term ?? ""
        }

        var content: Entry.Content? {
            guard !isGeneratingDefinition else { return nil }
            return try? Entry.Content(term: term, definition: definition)
        }

        var generatableTerm: String? {
            guard isModelAvailable, !isGeneratingDefinition else { return nil }
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !isTermTooLong else { return nil }
            return term
        }

        var isCreating: Bool {
            entry == nil
        }

        var isGenerateButtonEnabled: Bool {
            isGeneratingDefinition || generatableTerm != nil
        }

        var isGeneratingDefinition: Bool {
            generation.is(\.lookingUp) || generation.is(\.writing)
        }

        var isSubmittable: Bool {
            content != nil
        }

        var isTermTooLong: Bool {
            term.trimmingCharacters(in: .whitespacesAndNewlines).count > EntryForm.maximumGeneratableTermLength
        }

        var needsReplacementConfirmation: Bool {
            !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && definition != generatedDefinition?.text
        }

        var note: Note? {
            switch generation {
            case .failed(let error):
                return .failure(error)
            case .lookingUp, .writing:
                return nil
            case nil:
                let isDefinitionBlank = definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isModelAvailable && isTermTooLong && isDefinitionBlank {
                    return .termTooLong
                }
                guard let generatedDefinition, definition == generatedDefinition.text else { return nil }
                return .generated(correctForm: generatedDefinition.correctForm)
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case confirmationDialog(PresentationAction<ConfirmationDialog>)
        case definitionGenerated(String)
        case definitionGenerationFailed(any Error)
        case definitionGenerationFinished(correctForm: String?)
        case delegate(Delegate)
        case dictionaryEntryResponse(DictionaryEntry?)
        case dismissButtonTapped
        case generateDefinitionButtonTapped
        case saveButtonTapped
        case stopGeneratingButtonTapped
        case task

        @CasePathable
        enum Delegate {
            case didCreate(Entry)
            case didUpdate(Entry)
        }
    }

    enum CancelID {
        case generation
    }

    static let lookupTimeout = Duration.seconds(3)
    static let maximumGeneratableTermLength = 100

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.definitionClient) var definitionClient
    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.definition):
                clearFailure(&state)
                return .none

            case .binding(\.term):
                state.generatedDefinition?.correctForm = nil
                clearFailure(&state)
                return .none

            case .binding:
                return .none

            case .confirmationDialog(.presented(.confirmReplacement)):
                return generateDefinition(&state)

            case .confirmationDialog:
                return .none

            case .definitionGenerated(let definition):
                guard state.generation.is(\.writing) else { return .none }
                state.definition = definition
                return .none

            case .definitionGenerationFailed(let error):
                return failGeneration(&state, error: error)

            case .definitionGenerationFinished(let correctForm):
                guard state.generation.is(\.writing) else { return .none }
                guard !state.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return failGeneration(&state, error: DefinitionClient.GenerationError.failed)
                }
                state.completedGenerationCount += 1
                state.generatedDefinition = GeneratedDefinition(correctForm: correctForm, text: state.definition)
                state.generation = nil
                return .run { _ in await hapticsClient.success() }

            case .delegate:
                return .none

            case .dictionaryEntryResponse(let entry):
                guard case .lookingUp(let previousDefinition, let term) = state.generation else { return .none }
                state.generation = .writing(previousDefinition: previousDefinition)
                return streamDefinition(term: term, entry: entry)

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

            case .generateDefinitionButtonTapped:
                guard state.generatableTerm != nil else { return .none }
                guard !state.needsReplacementConfirmation else {
                    state.confirmationDialog = .confirmReplacement
                    return .none
                }
                return generateDefinition(&state)

            case .saveButtonTapped:
                guard let content = state.content else { return .none }
                do {
                    guard let original = state.entry else {
                        let entry = try Entry(content: content, createdAt: now, id: uuid(), isBookmarked: false)
                        return .send(.delegate(.didCreate(entry)))
                    }
                    let entry = try Entry(
                        content: content,
                        createdAt: original.createdAt,
                        id: original.id,
                        isBookmarked: original.isBookmarked
                    )
                    return .send(.delegate(.didUpdate(entry)))
                } catch {
                    reportIssue(error)
                    return .none
                }

            case .stopGeneratingButtonTapped:
                switch state.generation {
                case .lookingUp(let previousDefinition, _), .writing(let previousDefinition):
                    state.definition = previousDefinition
                    state.generation = nil
                    return .cancel(id: CancelID.generation)
                case .failed, nil:
                    return .none
                }

            case .task:
                state.isModelAvailable = definitionClient.isAvailable()
                guard state.isModelAvailable else { return .none }
                return .run { _ in definitionClient.prewarm() }
            }
        }
        .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
    }

    private func clearFailure(_ state: inout State) {
        guard state.generation.is(\.failed) else { return }
        state.generation = nil
    }

    private func failGeneration(_ state: inout State, error: any Error) -> Effect<Action> {
        guard case .writing(let previousDefinition) = state.generation else { return .none }
        logger.error("Generating the definition failed: \(error, privacy: .public)")
        state.definition = previousDefinition
        state.generation = .failed(error as? DefinitionClient.GenerationError ?? .failed)
        return .run { _ in await hapticsClient.warning() }
    }

    private func generateDefinition(_ state: inout State) -> Effect<Action> {
        guard let term = state.generatableTerm else { return .none }
        state.generation = .lookingUp(previousDefinition: state.definition, term: term)
        state.definition = ""
        return
            .run { [clock, dictionaryClient] send in
                let entry = await withTaskGroup(of: DictionaryEntry?.self) { group in
                    group.addTask {
                        do {
                            return try await dictionaryClient.entry(term: term)
                        } catch {
                            logger.info("Looking up the term failed: \(error, privacy: .private)")
                            return nil
                        }
                    }
                    group.addTask {
                        try? await clock.sleep(for: Self.lookupTimeout)
                        return nil
                    }
                    defer { group.cancelAll() }
                    return await group.next() ?? nil
                }
                await send(.dictionaryEntryResponse(entry))
            }
            .cancellable(id: CancelID.generation)
    }

    private func streamDefinition(term: String, entry: DictionaryEntry?) -> Effect<Action> {
        .run { send in
            do {
                for try await definition in definitionClient.definition(term: term, entry: entry) {
                    await send(.definitionGenerated(definition))
                }
                await send(.definitionGenerationFinished(correctForm: entry?.correctForm))
            } catch {
                await send(.definitionGenerationFailed(error))
            }
        }
        .cancellable(id: CancelID.generation)
    }
}

extension ConfirmationDialogState where Action == EntryForm.ConfirmationDialog {
    static let confirmReplacement = ConfirmationDialogState(titleVisibility: .visible) {
        TextState("Replace Your Definition?")
    } actions: {
        ButtonState(role: .destructive, action: .confirmReplacement) {
            TextState("Replace Definition")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("A generated definition will replace the one you wrote.")
    }
}

private let logger = Logger(category: "EntryForm")
