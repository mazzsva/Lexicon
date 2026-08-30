//
//  HomeTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 31/08/26.
//

import ComposableArchitecture
import Testing

@testable import Lexicon

@MainActor
struct HomeTests {
    @Test
    func deletingFromTheDetailPopsBackAndDeletesTheEntry() async {
        var state = Home.State(user: .mock)
        state.$entries.withLock { $0 = IdentifiedArray(uniqueElements: Entry.mocks) }
        state.path.append(EntryDetail.State(entry: SharedReader(value: .blueMoon)))
        let detailID = Array(state.path.ids)[0]

        await confirmation("Deletes the entry") { deletesEntry in
            let store = TestStore(initialState: state) {
                Home()
            } withDependencies: {
                $0.entriesClient.delete = { id, uid in
                    #expect(id == Entry.blueMoon.id)
                    #expect(uid == User.mock.uid)
                    deletesEntry()
                }
                $0.hapticsClient.warning = {}
            }

            await store.send(
                .path(.element(id: detailID, action: .delegate(.didDelete(Entry.blueMoon.id))))
            ) {
                $0.path.pop(from: detailID)
            }
            await store.finish()
        }
    }
}
