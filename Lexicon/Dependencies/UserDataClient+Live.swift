//
//  UserDataClient+Live.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 31/10/26.
//

import Dependencies

extension UserDataClient: DependencyKey {
    static var liveValue: UserDataClient {
        @Dependency(\.entriesClient) var entriesClient
        return UserDataClient(
            deleteAll: { uid, didDeleteSomeData in
                try await entriesClient.deleteAll(uid)
                await didDeleteSomeData()
            }
        )
    }
}
