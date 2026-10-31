//
//  UserDataClient.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 31/10/26.
//

import Dependencies
import DependenciesMacros

@DependencyClient
struct UserDataClient: Sendable {
    var deleteAll: @Sendable (_ uid: String, _ didDeleteSomeData: @Sendable () async -> Void) async throws -> Void
}

extension UserDataClient: TestDependencyKey {
    static var previewValue: UserDataClient {
        UserDataClient(deleteAll: { _, _ in })
    }

    static var testValue: UserDataClient {
        UserDataClient()
    }
}

extension DependencyValues {
    var userDataClient: UserDataClient {
        get { self[UserDataClient.self] }
        set { self[UserDataClient.self] = newValue }
    }
}
