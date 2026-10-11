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
                nonisolated(unsafe) let coordinator = NSFileCoordinator()
                let intent = NSFileAccessIntent.readingIntent(with: url)
                return try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await withCheckedThrowingContinuation { continuation in
                        coordinator.coordinate(with: [intent], queue: OperationQueue()) { error in
                            continuation.resume(
                                with: Result {
                                    if let error { throw error }
                                    let handle = try FileHandle(forReadingFrom: intent.url)
                                    defer { try? handle.close() }
                                    let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
                                    guard data.count <= maximumSize else { throw ReadError.tooLarge }
                                    return data
                                }
                            )
                        }
                    }
                } onCancel: {
                    coordinator.cancel()
                }
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
