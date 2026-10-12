//
//  EntryForm.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 20/07/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EntryForm {
    @ObservableState
    struct State: Equatable {
        var definition: String
        let entry: Entry?
        var term: String

        init(entry: Entry? = nil) {
            self.entry = entry
            definition = entry?.definition ?? ""
            term = entry?.term ?? ""
        }

        var content: Entry.Content? {
            try? Entry.Content(term: term, definition: definition)
        }

        var isCreating: Bool {
            entry == nil
        }

        var isSubmittable: Bool {
            content != nil
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case dismissButtonTapped
        case saveButtonTapped

        @CasePathable
        enum Delegate {
            case didCreate(Entry)
            case didUpdate(Entry)
        }
    }

    @Dependency(\.date.now) var now
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .delegate:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

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
            }
        }
    }
}
