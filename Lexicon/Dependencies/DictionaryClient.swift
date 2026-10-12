//
//  DictionaryClient.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct DictionaryClient: Sendable {
    var entry: @Sendable (_ term: String) async throws -> DictionaryEntry?
}

struct DictionaryEntry: Equatable, Sendable {
    let correctForm: String?
    let senses: [String]
    let title: String
}

extension DictionaryClient: DependencyKey {
    static var liveValue: DictionaryClient {
        DictionaryClient(
            entry: { term in
                let titles = term == term.lowercased() ? [term] : [term, term.lowercased()]
                if let entry = try await firstEntry(titles) {
                    return entry
                }
                let closestTitles = Wiktionary.closestTitles(try await search(term), to: term)
                if let entry = try await firstEntry(closestTitles.filter { !titles.contains($0) }) {
                    return entry
                }
                return try await firstEntry(existingTitles(Wiktionary.phrases(in: term)))
            }
        )
    }

    static var previewValue: DictionaryClient {
        DictionaryClient(entry: { _ in nil })
    }

    static var testValue: DictionaryClient {
        DictionaryClient()
    }

    private static func data(from url: URL) async throws -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("Lexicon (https://github.com/mazzsva/Lexicon)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            return data
        case 404:
            return nil
        default:
            throw URLError(.badServerResponse)
        }
    }

    private static func entry(title: String) async throws -> DictionaryEntry? {
        try await Wiktionary.entry(title: title, senses: senses(title: title)) { try await senses(title: $0) }
    }

    private static func existingTitles(_ titles: [String]) async throws -> [String] {
        guard !titles.isEmpty else { return [] }
        guard
            let data = try await data(from: try queryURL(["redirects": "1", "titles": titles.joined(separator: "|")]))
        else { return [] }
        return try Wiktionary.existingTitles(titles, from: data)
    }

    private static func firstEntry(_ titles: [String]) async throws -> DictionaryEntry? {
        for title in titles {
            if let entry = try await entry(title: title) {
                return entry
            }
        }
        return nil
    }

    private static func queryURL(_ parameters: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "en.wiktionary.org"
        components.path = "/w/api.php"
        components.queryItems =
            [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "formatversion", value: "2"),
            ] + parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private static func search(_ term: String) async throws -> [String] {
        struct Response: Decodable {
            struct Query: Decodable {
                struct Result: Decodable {
                    let title: String
                }

                let search: [Result]
            }

            let query: Query
        }

        let url = try queryURL(["list": "search", "srlimit": "3", "srprop": "", "srsearch": term])
        guard let data = try await data(from: url) else { return [] }
        return try JSONDecoder().decode(Response.self, from: data).query.search.map(\.title)
    }

    private static func senses(title: String) async throws -> [Wiktionary.Sense] {
        guard
            let url = URL(
                string:
                    "https://en.wiktionary.org/api/rest_v1/page/definition/\(Wiktionary.pathComponent(for: title))"
            )
        else { throw URLError(.badURL) }
        async let wikitext = self.wikitext(title: title)
        guard let data = try await data(from: url) else { return [] }
        let senses = try Wiktionary.senses(from: data)
        guard let wikitext = await wikitext else { return senses }
        return Wiktionary.labeled(senses, wikitext: wikitext)
    }

    private static func wikitext(title: String) async -> String? {
        guard
            let url = URL(
                string:
                    "https://en.wiktionary.org/w/index.php?title=\(Wiktionary.pathComponent(for: title))&action=raw"
            ),
            let data = try? await data(from: url)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DependencyValues {
    var dictionaryClient: DictionaryClient {
        get { self[DictionaryClient.self] }
        set { self[DictionaryClient.self] = newValue }
    }
}
