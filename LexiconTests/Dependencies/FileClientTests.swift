//
//  FileClientTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import CustomDump
import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct FileClientTests {
        let directory: URL

        init() throws {
            directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        @Test
        func theLiveReadReturnsTheContents() async throws {
            let url = try file(size: 10)

            let data = try await FileClient.liveValue.read(url: url, maximumSize: 10)

            expectNoDifference(data, Data(repeating: 65, count: 10))
        }

        @Test
        func theLiveReadRefusesAFileOverTheMaximumSize() async throws {
            let url = try file(size: 11)

            await #expect(throws: FileClient.ReadError.tooLarge) {
                try await FileClient.liveValue.read(url: url, maximumSize: 10)
            }
        }

        @Test
        func theLiveReadFollowsASymbolicLink() async throws {
            let target = try file(size: 4)
            let link = directory.appending(path: "Link.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let data = try await FileClient.liveValue.read(url: link, maximumSize: 10)

            expectNoDifference(data, Data(repeating: 65, count: 4))
        }

        @Test
        func theLiveReadFailsForAMissingFile() async {
            await #expect(throws: (any Error).self) {
                try await FileClient.liveValue.read(url: directory.appending(path: "Missing.json"), maximumSize: 10)
            }
        }

        @Test
        func theLiveReadFailsForADirectory() async throws {
            do {
                _ = try await FileClient.liveValue.read(url: directory, maximumSize: 10)
                Issue.record("The read of a directory succeeded.")
            } catch {
                #expect(!(error is FileClient.ReadError))
            }
        }

        private func file(size: Int) throws -> URL {
            let url = directory.appending(path: "\(UUID().uuidString).json")
            try Data(repeating: 65, count: size).write(to: url)
            return url
        }
    }
}
