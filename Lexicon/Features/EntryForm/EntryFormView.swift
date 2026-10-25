//
//  EntryFormView.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 20/07/26.
//

import ComposableArchitecture
import SwiftUI

struct EntryFormView: View {
    @Bindable var store: StoreOf<EntryForm>

    private static let definitionMinimumHeight: CGFloat = 180
    private static let definitionPadding = EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
    private static let definitionRowID = "definition"
    private static let generateButtonClearance: CGFloat = 40
    private static let generateButtonMargin: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFollowingGeneration = false
    @FocusState private var isDefinitionFocused: Bool
    @FocusState private var isTermFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section("Term") {
                        TextField("", text: $store.term)
                            .focused($isTermFocused)
                            .disabled(store.isGeneratingDefinition)
                            .accessibilityLabel("Term")
                    }
                    Section {
                        definitionRow
                    } header: {
                        Text("Definition")
                    } footer: {
                        footer
                    }
                }
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .groupedBackground()
                .onChange(of: store.definition) { definitionChanged(proxy) }
                .onScrollPhaseChange { _, phase in scrollPhaseChanged(phase) }
            }
            .navigationTitle(store.isCreating ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        store.send(.saveButtonTapped)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!store.isSubmittable)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") {
                        store.send(.dismissButtonTapped)
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                }
            }
            .onAppear { appeared() }
            .onChange(of: store.completedGenerationCount) { generationCompleted() }
            .onChange(of: store.isGeneratingDefinition) { _, isGenerating in generatingChanged(isGenerating) }
            .onChange(of: store.note) { _, note in noteChanged(note) }
            .onChange(of: isReduceMotionEnabled, initial: true) { store.isReduceMotionEnabled = isReduceMotionEnabled }
            .task { await store.send(.task).finish() }
        }
    }

    private var definitionClearance: CGFloat {
        store.isModelAvailable ? Self.generateButtonClearance : 0
    }

    private var definitionEditor: some View {
        TextEditor(text: $store.definition)
            .focused($isDefinitionFocused)
            .frame(minHeight: Self.definitionMinimumHeight - definitionClearance)
            .disabled(store.isGeneratingDefinition)
            .overlay(alignment: .topLeading) {
                Group {
                    if store.isGeneratingDefinition && store.definition.isEmpty {
                        GeneratingLabel()
                            .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    } else if !store.isGeneratingDefinition && store.definition.isEmpty {
                        placeholder
                            .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 5)
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.25), value: store.isGeneratingDefinition)
            .accessibilityLabel("Definition")
            .padding(.bottom, definitionClearance)
    }

    private var definitionRow: some View {
        ZStack(alignment: .bottomTrailing) {
            definitionEditor
                .padding(Self.definitionPadding)
            if store.isModelAvailable {
                if !store.isGeneratingDefinition {
                    Color.clear
                        .frame(height: Self.definitionPadding.bottom + Self.generateButtonClearance)
                        .contentShape(.rect)
                        .onTapGesture { isDefinitionFocused = true }
                        .accessibilityHidden(true)
                }
                generateButton
                    .padding(Self.generateButtonMargin)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.isModelAvailable)
        .id(Self.definitionRowID)
        .listRowInsets(EdgeInsets())
        .listRowBackground(
            GenerationGlow(
                completedGenerationCount: store.completedGenerationCount,
                definition: store.definition,
                generation: store.generation,
                isModelAvailable: store.isModelAvailable
            )
        )
    }

    private var footer: some View {
        ZStack(alignment: .topLeading) {
            if let note = store.note {
                Text(note.text)
                    .id(note)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.note)
    }

    private var generateButton: some View {
        let isGenerating = store.isGeneratingDefinition
        return Button {
            generateButtonTapped()
        } label: {
            ZStack {
                if isGenerating {
                    Image(systemName: "stop.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .transition(.blurReplace)
                } else {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(generateButtonStyle)
                        .transition(.blurReplace)
                }
            }
            .frame(width: 30, height: 30)
            .animation(.snappy(duration: 0.2), value: isGenerating)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(!store.isGenerateButtonEnabled)
        .confirmationDialog($store.scope(state: \.confirmationDialog, action: \.confirmationDialog))
        .accessibilityLabel(generateButtonTitle)
        .accessibilityHint(generateButtonHint)
        .accessibilityInputLabels(isGenerating ? ["Stop", "Stop Generating"] : ["Generate", "Generate Definition"])
        .accessibilityShowsLargeContentViewer {
            Label(generateButtonTitle, systemImage: isGenerating ? "stop.fill" : "sparkles")
        }
    }

    private var generateButtonHint: Text {
        if store.isGeneratingDefinition {
            Text("Stops writing and restores the previous definition.")
        } else if store.isGenerateButtonEnabled {
            Text("Writes a definition of the term.")
        } else if store.isTermTooLong {
            Text("Shorten the term first.")
        } else {
            Text("Enter a term first.")
        }
    }

    private var generateButtonStyle: AnyShapeStyle {
        store.isGenerateButtonEnabled ? AnyShapeStyle(generateGradient) : AnyShapeStyle(.tertiary)
    }

    private var generateGradient: LinearGradient {
        LinearGradient(
            colors: GenerationGlowSurface.palette(for: colorScheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var generateButtonTitle: LocalizedStringKey {
        store.isGeneratingDefinition ? "Stop Generating" : "Generate Definition"
    }

    private var placeholder: some View {
        Text("Write or generate a definition.")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func appeared() {
        guard store.isCreating else { return }
        isTermFocused = true
    }

    private func definitionChanged(_ proxy: ScrollViewProxy) {
        guard store.isGeneratingDefinition, isFollowingGeneration else { return }
        withAnimation(.smooth(duration: 0.3)) {
            proxy.scrollTo(Self.definitionRowID, anchor: .bottom)
        }
    }

    private func generateButtonTapped() {
        guard store.isGeneratingDefinition else {
            store.send(.generateDefinitionButtonTapped)
            return
        }
        store.send(.stopGeneratingButtonTapped)
        guard isVoiceOverEnabled else { return }
        AccessibilityNotification.Announcement(AttributedString(localized: "Stopped writing")).post()
    }

    private func generatingChanged(_ isGenerating: Bool) {
        if isGenerating {
            isFollowingGeneration = true
        }
        guard isGenerating, isVoiceOverEnabled else { return }
        AccessibilityNotification.Announcement(AttributedString(localized: "Writing definition")).post()
    }

    private func generationCompleted() {
        guard isVoiceOverEnabled, let note = store.note else { return }
        var announcement = AttributedString(localized: note.text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func noteChanged(_ note: EntryForm.Note?) {
        guard isVoiceOverEnabled, let note else { return }
        var announcement = AttributedString(localized: note.text)
        switch note {
        case .failure:
            announcement.accessibilitySpeechAnnouncementPriority = .high
        case .generated:
            return
        case .termTooLong:
            guard isTermFocused || isDefinitionFocused else { return }
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func scrollPhaseChanged(_ phase: ScrollPhase) {
        guard phase == .interacting else { return }
        isFollowingGeneration = false
    }
}

extension EntryForm.Note {
    fileprivate var text: LocalizedStringResource {
        switch self {
        case .failure(.failed):
            "The definition couldn't be generated. Write it yourself, or try again later."
        case .failure(.unknownTerm):
            "Lexicon doesn't know this term. Check the spelling, or write the definition yourself."
        case .failure(.unsupportedLanguage):
            "Lexicon can't define terms in this language yet."
        case .failure(.unsupportedTerm):
            "Lexicon can't define this term."
        case .generated(let correctForm?):
            "Did you mean “\(correctForm)”? Check the generated definition for mistakes."
        case .generated(nil):
            "Check the generated definition for mistakes."
        case .termTooLong:
            "Lexicon can generate definitions for terms of up to \(EntryForm.maximumGeneratableTermLength) characters."
        }
    }
}

private struct GeneratingLabel: View {
    var body: some View {
        Label("Writing…", systemImage: "sparkles")
            .symbolEffect(.variableColor.iterative)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

#Preview("Create") {
    EntryFormView(
        store: Store(initialState: EntryForm.State()) {
            EntryForm()
        }
    )
}

#Preview("Edit") {
    EntryFormView(
        store: Store(initialState: EntryForm.State(entry: .blueMoon)) {
            EntryForm()
        }
    )
}

#Preview(
    "Unavailable",
    traits: .dependencies {
        $0.definitionClient.isAvailable = { false }
    }
) {
    EntryFormView(
        store: Store(initialState: EntryForm.State()) {
            EntryForm()
        }
    )
}
