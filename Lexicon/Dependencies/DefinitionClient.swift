//
//  DefinitionClient.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import Dependencies
import DependenciesMacros
import Foundation
import FoundationModels

@DependencyClient
struct DefinitionClient: Sendable {
    enum GenerationError: Error {
        case failed
        case unknownTerm
        case unsupportedLanguage
        case unsupportedTerm
    }

    var definition: @Sendable (_ term: String, _ entry: DictionaryEntry?) -> AsyncThrowingStream<String, any Error> = {
        _, _ in .finished()
    }
    var isAvailable: @Sendable () -> Bool = { false }
    var prewarm: @Sendable () -> Void
}

extension DefinitionClient {
    private static let unknownTermReply = "UNKNOWN"

    static func definition(fromReply reply: String) -> String? {
        let definition = firstLine(of: reply)
            .replacing(#/\h*(?:—|--)\h*|\h+–\h+/#, with: ", ")
            .trimmingCharacters(in: .whitespaces)
        guard !unknownTermReply.hasPrefix(definition.uppercased().trimmingCharacters(in: ["."])) else { return nil }
        return definition
    }

    static func definitions<Replies: AsyncSequence>(
        in replies: Replies,
        isInDictionary: Bool,
        yield: (String) -> Void
    ) async throws where Replies.Element == String {
        var reply = ""
        var shown: String?
        for try await snapshot in replies {
            reply = snapshot
            if let definition = definition(fromReply: reply), definition != shown {
                shown = definition
                yield(definition)
            }
            if reply.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isNewline) {
                break
            }
        }
        guard !isUnknownTerm(reply: reply) else {
            throw isInDictionary ? GenerationError.failed : GenerationError.unknownTerm
        }
        guard definition(fromReply: reply) != nil else { throw GenerationError.failed }
    }

    static func isUnknownTerm(reply: String) -> Bool {
        firstLine(of: reply).uppercased().trimmingCharacters(in: ["."]) == unknownTermReply
    }

    static func prompt(term: String, entry: DictionaryEntry?) -> String {
        let correctForm = entry?.correctForm.map { "Correct form: \($0)\n" } ?? ""
        let senses = entry.map { "Senses:\n" + $0.senses.map { "- \($0)\n" }.joined() } ?? ""
        return "Term: \(entry?.title ?? term)\n\(correctForm)\(senses)Definition:"
    }

    private static func firstLine(of reply: String) -> String {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { !$0.isNewline }
            .trimmingCharacters(in: .whitespaces)
    }
}

extension DefinitionClient: DependencyKey {
    static var liveValue: DefinitionClient {
        let prewarmedSession = LockIsolated<LanguageModelSession?>(nil)
        return DefinitionClient(
            definition: { term, entry in
                let session =
                    prewarmedSession.withValue { session in
                        defer { session = nil }
                        return session
                    } ?? makeSession()
                return AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            let replies = session.streamResponse(
                                to: prompt(term: term, entry: entry),
                                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 60)
                            )
                            try await definitions(in: replies.map(\.content), isInDictionary: entry != nil) {
                                continuation.yield($0)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: generationError(for: error))
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            isAvailable: {
                SystemLanguageModel.default.isAvailable
            },
            prewarm: {
                let session = makeSession()
                session.prewarm()
                prewarmedSession.setValue(session)
            }
        )
    }

    static var previewValue: DefinitionClient {
        DefinitionClient(
            definition: { _, _ in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        let words = Entry.blueMoon.definition.split(separator: " ")
                        try await Task.sleep(for: .seconds(1))
                        for count in words.indices {
                            continuation.yield(words[...count].joined(separator: " "))
                            try await Task.sleep(for: .milliseconds(80))
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            isAvailable: { true },
            prewarm: {}
        )
    }

    static var testValue: DefinitionClient {
        DefinitionClient()
    }
}

extension DefinitionClient {
    private struct Demonstration {
        let definition: String?
        let entry: DictionaryEntry?
        let term: String
    }

    private static let demonstrations = [
        Demonstration(
            definition: "Something that is very easy to do.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: ["A walk through a park.", "(idiomatic) Something that is easy to do."],
                title: "a walk in the park"
            ),
            term: "a walk in the park"
        ),
        Demonstration(
            definition: "To decide to do something later, or to make someone dislike something.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: [
                    "(archaic) To take off (clothing).", "To delay (something); to postpone.",
                    "To cause (someone) to dislike something.",
                ],
                title: "put off"
            ),
            term: "put off"
        ),
        Demonstration(
            definition: "Feeling so surprised that you cannot speak, said mostly in the UK.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: [
                    "(UK, Ireland, slang) Astonished, amazed; so surprised as to be lost for words."
                ],
                title: "gobsmacked"
            ),
            term: "gobsmacked"
        ),
        Demonstration(
            definition: "A rude word for something that is bad, useless, or not true.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: ["(vulgar) Feces.", "(vulgar, slang) Something of poor quality; nonsense."],
                title: "crap"
            ),
            term: "crap"
        ),
        Demonstration(
            definition: "Feeling angry or annoyed because you are hungry.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: ["(informal) Irritable as a result of hunger."],
                title: "hangry"
            ),
            term: "hangry"
        ),
        Demonstration(
            definition: "Reading bad news on your phone for a long time, even though it makes you feel worse.",
            entry: nil,
            term: "doomscrolling"
        ),
        Demonstration(
            definition: "You say this when you are very surprised, or to say a strong no.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: [
                    "Used to express disbelief or surprise.", "Absolutely not; used as a strong refusal.",
                ],
                title: "no way"
            ),
            term: "no way"
        ),
        Demonstration(
            definition: "Short for “I don’t know”, used in texts and chats.",
            entry: DictionaryEntry(
                correctForm: nil,
                senses: ["(Internet slang) Initialism of I don't know."],
                title: "IDK"
            ),
            term: "IDK"
        ),
        Demonstration(
            definition: "A world where people will do anything, even hurt others, to win.",
            entry: DictionaryEntry(
                correctForm: "dog-eat-dog world",
                senses: ["(idiomatic) A world or situation of ruthless competition."],
                title: "doggy dog world"
            ),
            term: "doggy dog world"
        ),
        Demonstration(definition: nil, entry: nil, term: "plimbering"),
    ]

    private static let instructions = """
        You write a learner's dictionary for people who are learning English. For each term, write one short \
        sentence in simple, everyday words that explains what people mean by it in conversation today. Say when it \
        is rude. Skip senses that are old, rare, or literal. When a correct form is given, explain that. Reply with \
        only the sentence, or with only \(unknownTermReply) when you don't know the term.
        """

    private static func generationError(for error: any Error) -> any Error {
        if #available(iOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal:
                return GenerationError.unsupportedTerm
            case .unsupportedLanguageOrLocale:
                return GenerationError.unsupportedLanguage
            default:
                return error
            }
        }
        guard let error = error as? LanguageModelSession.GenerationError else { return error }
        switch error {
        case .guardrailViolation, .refusal:
            return GenerationError.unsupportedTerm
        case .unsupportedLanguageOrLocale:
            return GenerationError.unsupportedLanguage
        default:
            return error
        }
    }

    private static func makeSession() -> LanguageModelSession {
        var entries = [
            Transcript.Entry.instructions(Transcript.Instructions(segments: [text(instructions)], toolDefinitions: []))
        ]
        for demonstration in demonstrations {
            entries.append(
                .prompt(
                    Transcript.Prompt(segments: [text(prompt(term: demonstration.term, entry: demonstration.entry))]))
            )
            entries.append(
                .response(
                    Transcript.Response(
                        assetIDs: [],
                        segments: [text(demonstration.definition ?? unknownTermReply)]
                    )
                )
            )
        }
        return LanguageModelSession(
            model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
            transcript: Transcript(entries: entries)
        )
    }

    private static func text(_ content: String) -> Transcript.Segment {
        .text(Transcript.TextSegment(content: content))
    }
}

extension DependencyValues {
    var definitionClient: DefinitionClient {
        get { self[DefinitionClient.self] }
        set { self[DefinitionClient.self] = newValue }
    }
}
