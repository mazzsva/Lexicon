//
//  EntriesArchive.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum EntriesArchive {
    enum ReadError: Error, Equatable {
        case invalid
        case unsupportedVersion
    }

    struct Record: Equatable, Sendable {
        var createdAt: Date?
        var definition: String?
        var id: UUID?
        var isBookmarked: Bool?
        var term: String?
    }

    static let maximumFileSize = 100_000_000
    static let version = 1

    static func data(for entries: [Entry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(entries: entries.map(EncodedEntry.init), version: version))
    }

    static func records(from data: Data) throws(ReadError) -> [Record] {
        do {
            return try JSONDecoder().decode(DecodedEnvelope.self, from: data).entries.map(\.record)
        } catch let error as ReadError {
            throw error
        } catch {
            throw .invalid
        }
    }
}

extension EntriesArchive {
    struct Import: Equatable, Sendable {
        var duplicateCount = 0
        var entries: [Entry] = []
        var invalidCount = 0

        init(records: [Record], existing: [Entry], now: Date, uuid: () -> UUID) {
            let existingIDs = Set(existing.map(\.id))
            var contents = Set(existing.map(\.content))
            for record in records {
                if let id = record.id, existingIDs.contains(id) {
                    duplicateCount += 1
                    continue
                }
                guard let content = try? Entry.Content(term: record.term ?? "", definition: record.definition ?? "")
                else {
                    invalidCount += 1
                    continue
                }
                guard !contents.contains(content) else {
                    duplicateCount += 1
                    continue
                }
                guard
                    let entry = try? Entry(
                        content: content,
                        createdAt: record.createdAt ?? now,
                        id: uuid(),
                        isBookmarked: record.isBookmarked ?? false
                    )
                else {
                    invalidCount += 1
                    continue
                }
                contents.insert(content)
                entries.append(entry)
            }
        }
    }
}

extension EntriesArchive {
    struct Export: Transferable {
        let entries: [Entry]

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .json) { export in
                try EntriesArchive.data(for: export.entries)
            }
            .suggestedFileName { _ in
                fileName(date: .now, timeZone: .current)
            }
        }

        static func fileName(date: Date, timeZone: TimeZone) -> String {
            "Lexicon \(date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())).json"
        }
    }
}

extension EntriesArchive {
    private struct Envelope: Encodable {
        let entries: [EncodedEntry]
        let version: Int
    }

    private struct EncodedEntry: Encodable {
        let createdAt: String
        let definition: String
        let id: UUID
        let isBookmarked: Bool
        let term: String

        init(_ entry: Entry) {
            createdAt = timestamp(entry.createdAt)
            definition = entry.definition
            id = entry.id
            isBookmarked = entry.isBookmarked
            term = entry.term
        }
    }

    private struct DecodedEnvelope: Decodable {
        let entries: [DecodedEntry]

        enum CodingKeys: String, CodingKey {
            case entries
            case version
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .version)
            guard version >= 1 else { throw ReadError.invalid }
            guard version <= EntriesArchive.version else { throw ReadError.unsupportedVersion }
            entries = try container.decode([DecodedEntry].self, forKey: .entries)
        }
    }

    private struct DecodedEntry: Decodable {
        let record: Record

        enum CodingKeys: String, CodingKey {
            case createdAt
            case definition
            case id
            case isBookmarked
            case term
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
            let id = try? container.decodeIfPresent(String.self, forKey: .id)
            record = Record(
                createdAt: createdAt.flatMap { try? Date($0, strategy: dateFormat) },
                definition: try? container.decodeIfPresent(String.self, forKey: .definition),
                id: id.flatMap(UUID.init(uuidString:)),
                isBookmarked: try? container.decodeIfPresent(Bool.self, forKey: .isBookmarked),
                term: try? container.decodeIfPresent(String.self, forKey: .term)
            )
        }
    }

    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func timestamp(_ date: Date) -> String {
        let microseconds = (date.timeIntervalSince1970 * 1_000_000).rounded()
        let seconds = (microseconds / 1_000_000).rounded(.down)
        let fraction = Int(microseconds - seconds * 1_000_000)
        let whole = Date(timeIntervalSince1970: seconds).formatted(.iso8601)
        return "\(whole.dropLast()).\(String(format: "%06d", fraction))Z"
    }
}
