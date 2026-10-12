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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isTermFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Term") {
                    TextField("", text: $store.term)
                        .focused($isTermFocused)
                        .disabled(store.isGeneratingDefinition)
                        .accessibilityLabel("Term")
                }
                Section {
                    TextEditor(text: $store.definition)
                        .frame(minHeight: 180)
                        .disabled(store.isGeneratingDefinition)
                        .overlay(alignment: .topLeading) {
                            if store.isGeneratingDefinition && store.definition.isEmpty {
                                GeneratingLabel()
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: store.isGeneratingDefinition)
                        .accessibilityLabel("Definition")
                        .listRowBackground(GenerationGlow(isActive: store.isGeneratingDefinition))
                } header: {
                    definitionHeaderLayout {
                        Text("Definition")
                        Spacer()
                        if store.isModelAvailable {
                            generateButton
                        }
                    }
                } footer: {
                    footer
                }
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .groupedBackground()
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
            .onChange(of: store.note) { _, note in noteChanged(note) }
            .task { await store.send(.task).finish() }
        }
    }

    private var definitionHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
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
            store.send(isGenerating ? .stopGeneratingButtonTapped : .generateDefinitionButtonTapped)
        } label: {
            HStack(spacing: 5) {
                Text(isGenerating ? "Stop" : "Generate")
                Image(systemName: isGenerating ? "stop.fill" : "sparkles")
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.default, value: isGenerating)
            }
        }
        .font(.subheadline)
        .fontWeight(.semibold)
        .textCase(nil)
        .disabled(!store.isGenerateButtonEnabled)
        .confirmationDialog($store.scope(state: \.confirmationDialog, action: \.confirmationDialog))
        .accessibilityLabel(isGenerating ? "Stop Generating" : "Generate Definition")
    }

    private func appeared() {
        guard store.isCreating else { return }
        isTermFocused = true
    }

    private func noteChanged(_ note: EntryForm.Note?) {
        guard let note else { return }
        var announcement = AttributedString(localized: note.text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
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
        }
    }
}

private struct GeneratingLabel: View {
    var body: some View {
        Label("Writing…", systemImage: "sparkles")
            .symbolEffect(.variableColor.iterative)
            .foregroundStyle(.secondary)
    }
}

private struct GenerationGlow: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color(.secondarySystemGroupedBackground)
            .overlay {
                if isActive {
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        Rectangle()
                            .strokeBorder(
                                AngularGradient(
                                    colors: [.blue, .purple, .pink, .orange, .yellow, .blue],
                                    center: .center,
                                    angle: .degrees(
                                        (context.date.timeIntervalSinceReferenceDate * 120)
                                            .truncatingRemainder(dividingBy: 360)
                                    )
                                ),
                                lineWidth: 8
                            )
                            .blur(radius: 8)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isActive)
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
