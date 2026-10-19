//
//  EntryDetail.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EntryDetail {
    enum Alert: Equatable {
        case confirmDeletion
    }

    @Reducer
    enum Destination {
        case alert(AlertState<EntryDetail.Alert>)
        case editEntry(EntryForm)
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
        @SharedReader var entry: Entry
    }

    enum Action {
        case bookmarkButtonTapped
        case delegate(Delegate)
        case deleteButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case editButtonTapped

        @CasePathable
        enum Delegate {
            case didChangeBookmark(Bool)
            case didDelete
            case didUpdate(Entry.Content)
        }
    }

    @Dependency(\.hapticsClient) var hapticsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .bookmarkButtonTapped:
                return .merge(
                    .run { _ in await hapticsClient.selection() },
                    .send(.delegate(.didChangeBookmark(!state.entry.isBookmarked)))
                )

            case .delegate:
                return .none

            case .deleteButtonTapped:
                state.destination = .alert(.confirmDeletion)
                return .none

            case .destination(.presented(.alert(.confirmDeletion))):
                return .send(.delegate(.didDelete))

            case .destination(.presented(.editEntry(.delegate(.didUpdate(let content))))):
                state.destination = nil
                return .merge(
                    .run { _ in await hapticsClient.success() },
                    .send(.delegate(.didUpdate(content)))
                )

            case .destination:
                return .none

            case .editButtonTapped:
                state.destination = .editEntry(EntryForm.State(entry: state.entry))
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension EntryDetail.Destination.State: Equatable {}

extension AlertState where Action == EntryDetail.Alert {
    static let confirmDeletion = AlertState {
        TextState("Delete Entry")
    } actions: {
        ButtonState(role: .destructive, action: .confirmDeletion) {
            TextState("Delete")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Are you sure you want to delete this entry?")
    }
}
