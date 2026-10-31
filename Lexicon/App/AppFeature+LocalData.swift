//
//  AppFeature+LocalData.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 31/10/26.
//

import ComposableArchitecture

extension AppFeature {
    func clearAppLocalData() async throws {
        @Dependency(\.entriesClient) var entriesClient
        try await entriesClient.clearLocalData()
    }
}
