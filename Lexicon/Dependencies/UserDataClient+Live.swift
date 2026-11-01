//
//  UserDataClient+Live.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 31/10/26.
//

import Dependencies

extension UserDataClient: DependencyKey {
    static var liveValue: UserDataClient {
        UserDataClient(
            deleteAll: { uid, didDeleteSomeData in
                try await FirestoreStorage.shared.deleteAll(uid: uid)
                await didDeleteSomeData()
            }
        )
    }
}
