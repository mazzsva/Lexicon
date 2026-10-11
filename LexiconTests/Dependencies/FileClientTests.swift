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
    final class FileClientTests {
        let directory: URL

        init() throws {
            directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
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

        @Test(arguments: [false, true])
        func theLiveReadFailsForAFileItCannotRead(isDirectory: Bool) async {
            let url = isDirectory ? directory : directory.appending(path: "Missing.json")

            let error = await #expect(throws: (any Error).self) {
                try await FileClient.liveValue.read(url: url, maximumSize: 10)
            }

            #expect(!(error is FileClient.ReadError))
        }

        private func file(size: Int) throws -> URL {
            let url = directory.appending(path: "\(UUID().uuidString).json")
            try Data(repeating: 65, count: size).write(to: url)
            return url
        }
    }
}
