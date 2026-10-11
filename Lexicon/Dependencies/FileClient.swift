//
//  FileClient.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct FileClient: Sendable {
    enum ReadError: Error {
        case tooLarge
    }

    var read: @Sendable (_ url: URL, _ maximumSize: Int) async throws -> Data
}

extension FileClient: DependencyKey {
    static var liveValue: FileClient {
        FileClient(
            read: { url, maximumSize in
                let isAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if isAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                var coordinationError: NSError?
                var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
                NSFileCoordinator()
                    .coordinate(readingItemAt: url, error: &coordinationError) { url in
                        result = Result {
                            let handle = try FileHandle(forReadingFrom: url)
                            defer { try? handle.close() }
                            let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
                            guard data.count <= maximumSize else { throw ReadError.tooLarge }
                            return data
                        }
                    }
                if let coordinationError {
                    throw coordinationError
                }
                return try result.get()
            }
        )
    }

    static var previewValue: FileClient {
        FileClient(
            read: { _, _ in
                try EntriesArchive.data(for: Entry.mocks)
            }
        )
    }

    static var testValue: FileClient {
        FileClient()
    }
}

extension DependencyValues {
    var fileClient: FileClient {
        get { self[FileClient.self] }
        set { self[FileClient.self] = newValue }
    }
}
