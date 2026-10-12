//
//  DefinitionClientTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import CustomDump
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct DefinitionClientTests {
        @Test
        func aReplyIsShownTrimmed() {
            expectNoDifference(
                DefinitionClient.definition(fromReply: " \n Something that happens very rarely. \n"),
                "Something that happens very rarely."
            )
        }

        @Test
        func thePromptListsTheDictionaryNotes() {
            expectNoDifference(
                DefinitionClient.prompt(term: "nip it in the butt", entry: nil),
                "Term: nip it in the butt\nDefinition:"
            )
            expectNoDifference(
                DefinitionClient.prompt(
                    term: "nip it in the butt",
                    entry: DictionaryEntry(
                        correctForm: "nip in the bud",
                        senses: ["To stop something early."],
                        title: "nip it in the butt"
                    )
                ),
                """
                Term: nip it in the butt
                Correct form: nip in the bud
                Senses:
                - To stop something early.
                Definition:
                """
            )
        }

        @Test
        func thePromptNamesTheTermThatTheSensesBelongTo() {
            let entry = DictionaryEntry(
                correctForm: nil,
                senses: ["To solve a famously difficult or impossible problem."],
                title: "square the circle"
            )

            expectNoDifference(
                DefinitionClient.prompt(term: "Trying to square the circle", entry: entry),
                """
                Term: square the circle
                Senses:
                - To solve a famously difficult or impossible problem.
                Definition:
                """
            )
        }

        @Test
        func aReplyEndsAtItsFirstLine() {
            expectNoDifference(
                DefinitionClient.definition(fromReply: "\nVery drunk.\n\nTerm: piss off"),
                "Very drunk."
            )
        }

        @Test(arguments: [
            "I’m tired—I’ll just give up.",
            "I’m tired — I’ll just give up.",
            "I’m tired – I’ll just give up.",
            "I’m tired -- I’ll just give up.",
        ])
        func aDashInAReplyIsShownAsAComma(reply: String) {
            expectNoDifference(DefinitionClient.definition(fromReply: reply), "I’m tired, I’ll just give up.")
        }

        @Test
        func hyphensAndRangesInAReplyAreKept() {
            expectNoDifference(
                DefinitionClient.definition(fromReply: "A well-known shop, open 9–5."),
                "A well-known shop, open 9–5."
            )
        }

        @Test(arguments: ["", " \n ", "U", "UNK", "UNKNOWN", " UNKNOWN.", "UNKNOWN\n", "Un", "Unknown.", "unknown"])
        func aReplyThatCanBeTheUnknownTermReplyIsNotShown(reply: String) {
            expectNoDifference(DefinitionClient.definition(fromReply: reply), nil)
        }

        @Test
        func aDefinitionThatStartsLikeTheUnknownTermReplyIsShown() {
            expectNoDifference(DefinitionClient.definition(fromReply: "Unable"), "Unable")
            expectNoDifference(
                DefinitionClient.definition(fromReply: "Unknown to most people."),
                "Unknown to most people."
            )
        }

        @Test
        func onlyTheUnknownTermReplyMeansAnUnknownTerm() {
            #expect(DefinitionClient.isUnknownTerm(reply: " UNKNOWN."))
            #expect(DefinitionClient.isUnknownTerm(reply: "Unknown\n\nTerm: piss off"))
            #expect(!DefinitionClient.isUnknownTerm(reply: "UNK"))
            #expect(!DefinitionClient.isUnknownTerm(reply: "Unknown to most people."))
        }

        @Test
        func theDefinitionGrowsUntilItsFirstLineEnds() async throws {
            var shown: [String] = []

            try await DefinitionClient.definitions(
                in: Self.replies("Very", "Very drunk.", "Very drunk.\n", "Very drunk.\nTerm: piss off"),
                isInDictionary: false
            ) { shown.append($0) }

            expectNoDifference(shown, ["Very", "Very drunk."])
        }

        @Test
        func theUnknownTermReplyIsNeverShown() async {
            var shown: [String] = []

            await #expect(throws: DefinitionClient.GenerationError.unknownTerm) {
                try await DefinitionClient.definitions(
                    in: Self.replies("U", "UNK", "UNKNOWN"),
                    isInDictionary: false
                ) { shown.append($0) }
            }
            expectNoDifference(shown, [])
        }

        @Test
        func theUnknownTermReplyForATermInTheDictionaryFails() async {
            await #expect(throws: DefinitionClient.GenerationError.failed) {
                try await DefinitionClient.definitions(in: Self.replies("UNKNOWN"), isInDictionary: true) { _ in }
            }
        }

        @Test
        func anEmptyReplyFails() async {
            await #expect(throws: DefinitionClient.GenerationError.failed) {
                try await DefinitionClient.definitions(in: Self.replies(" ", "\n"), isInDictionary: false) { _ in }
            }
        }

        private static func replies(_ replies: String...) -> AsyncThrowingStream<String, any Error> {
            AsyncThrowingStream { continuation in
                for reply in replies {
                    continuation.yield(reply)
                }
                continuation.finish()
            }
        }
    }
}
