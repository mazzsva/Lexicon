//
//  WiktionaryTests.swift
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
    struct WiktionaryTests {
        @Test
        func theSensesKeepOnlyTheDefinitionText() throws {
            let data = Data(
                #"""
                {
                  "en": [
                    {
                      "partOfSpeech": "Verb",
                      "definitions": [
                        { "definition": "To tease or mock (someone). <style data-mw-deduplicate=\"x\">.mw-parser-output .object-usage-tag{font-style:italic}</style>" },
                        { "definition": "<span class=\"mw-cite-backlink\"><a href=\"#cite\">1</a></span> A cited source" },
                        { "definition": "Used other than figuratively or idiomatically: see take, piss." },
                        { "definition": "fish &amp; chips" },
                        { "definition": "To move swiftly.\n<ol><li>To move forward on two feet." },
                        { "definition": "To move forward on two feet. [with out of]" }
                      ]
                    },
                    {
                      "partOfSpeech": "Symbol",
                      "definitions": [{ "definition": "A language code." }]
                    }
                  ],
                  "it": [
                    {
                      "partOfSpeech": "Interjection",
                      "definitions": [{ "definition": "<span>what a drag!</span>" }]
                    }
                  ]
                }
                """#
                .utf8
            )

            expectNoDifference(
                try Wiktionary.senses(from: data),
                [
                    Wiktionary.Sense(formOf: nil, language: "en", text: "To tease or mock (someone)."),
                    Wiktionary.Sense(formOf: nil, language: "en", text: "Fish & chips."),
                    Wiktionary.Sense(formOf: nil, language: "en", text: "To move swiftly."),
                    Wiktionary.Sense(formOf: nil, language: "en", text: "To move forward on two feet."),
                    Wiktionary.Sense(formOf: nil, language: "it", text: "What a drag!"),
                ]
            )
        }

        @Test
        func onlyACorrectionLinkMarksAMistake() {
            let eggcorn = """
                <span class="form-of-definition use-with-mention">Eggcorn of <span class="form-of-definition-link">\
                <i><a rel="mw:WikiLink" href="/wiki/for_all_intents_and_purposes#English">for all intents and \
                purposes</a></i></span></span>
                """
            let plural = """
                <span class="form-of-definition use-with-mention">plural of <span class="form-of-definition-link">\
                <i><a rel="mw:WikiLink" href="/wiki/umbrella#English">umbrella</a></i></span></span>
                """

            expectNoDifference(
                Wiktionary.sense(fromHTML: eggcorn, language: "en"),
                Wiktionary.Sense(
                    formOf: Wiktionary.FormOf(isCorrection: true, title: "for all intents and purposes"),
                    language: "en",
                    text: "Eggcorn of for all intents and purposes."
                )
            )
            expectNoDifference(
                Wiktionary.sense(fromHTML: plural, language: "en"),
                Wiktionary.Sense(
                    formOf: Wiktionary.FormOf(isCorrection: false, title: "umbrella"),
                    language: "en",
                    text: "Plural of umbrella."
                )
            )
        }

        @Test
        func anAbbreviationIsItsOwnSense() {
            let html = """
                <span class="form-of-definition use-with-mention">Initialism of <span class="form-of-definition-link">\
                <i><a rel="mw:WikiLink" href="/wiki/for_your_information#English">for your information</a></i>\
                </span></span>
                """

            expectNoDifference(
                Wiktionary.sense(fromHTML: html, language: "en"),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Initialism of for your information.")
            )
        }

        @Test
        func theFormOfLinkIsTheOneInsideItsSpan() {
            let html = """
                Misspelling of <span class="form-of-definition-link"><a class="new">teh</a></span> \
                <a rel="mw:WikiLink" href="/wiki/the">the</a>
                """

            expectNoDifference(
                Wiktionary.sense(fromHTML: html, language: "en"),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Misspelling of teh the.")
            )
        }

        @Test
        func anEntryUsesTheFirstTwoSensesOfOneLanguage() async throws {
            let senses = [
                Wiktionary.Sense(formOf: nil, language: "af", text: "Without."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Illumination by gas."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Illumination by gas."),
                Wiktionary.Sense(
                    formOf: Wiktionary.FormOf(isCorrection: false, title: "gaslight"),
                    language: "en",
                    text: "Present participle of gaslight."
                ),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Manipulation."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "A third sense."),
            ]

            let entry = try await Self.entry(senses)

            expectNoDifference(
                entry,
                DictionaryEntry(correctForm: nil, senses: ["Illumination by gas.", "Manipulation."], title: "x")
            )
        }

        @Test
        func aPageWithoutSensesHasNoEntry() async throws {
            let entry = try await Self.entry([])

            expectNoDifference(entry, nil)
        }

        @Test
        func aPageWithItsOwnSensesKeepsThem() async throws {
            let senses = [
                Wiktionary.Sense(
                    formOf: Wiktionary.FormOf(isCorrection: false, title: "light"),
                    language: "en",
                    text: "Simple past of light."
                ),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Exciting, excellent."),
            ]

            let entry = try await Wiktionary.entry(title: "lit", senses: senses) { title in
                Issue.record("Followed the link to \(title)")
                return []
            }

            expectNoDifference(entry, DictionaryEntry(correctForm: nil, senses: ["Exciting, excellent."], title: "lit"))
        }

        @Test
        func aPageWithOnlyALinkUsesTheLinkedSenses() async throws {
            let link = { (isCorrection: Bool) in
                [
                    Wiktionary.Sense(
                        formOf: Wiktionary.FormOf(isCorrection: isCorrection, title: "nip in the bud"),
                        language: "en",
                        text: "Form of nip in the bud."
                    )
                ]
            }
            let linked = [Wiktionary.Sense(formOf: nil, language: "en", text: "To stop something early.")]

            let followed = { (title: String) in
                expectNoDifference(title, "nip in the bud")
                return linked
            }

            let correction = try await Wiktionary.entry(
                title: "nip it in the butt", senses: link(true), formOfSenses: followed)
            let alternative = try await Wiktionary.entry(
                title: "nip it in the bud", senses: link(false), formOfSenses: followed)

            expectNoDifference(
                correction,
                DictionaryEntry(
                    correctForm: "nip in the bud",
                    senses: ["To stop something early."],
                    title: "nip it in the butt"
                )
            )
            expectNoDifference(
                alternative,
                DictionaryEntry(correctForm: nil, senses: ["To stop something early."], title: "nip it in the bud")
            )
        }

        @Test
        func aLinkedPageKeepsTheLanguageOfThePage() async throws {
            let senses = [
                Wiktionary.Sense(
                    formOf: Wiktionary.FormOf(isCorrection: false, title: "palla"),
                    language: "it",
                    text: "Plural of palla."
                )
            ]

            let entry = try await Wiktionary.entry(title: "palle", senses: senses) { _ in
                [
                    Wiktionary.Sense(formOf: nil, language: "en", text: "Pall."),
                    Wiktionary.Sense(formOf: nil, language: "it", text: "Ball."),
                ]
            }

            expectNoDifference(entry, DictionaryEntry(correctForm: nil, senses: ["Ball."], title: "palle"))
        }

        @Test
        func theWikitextGivesEachSenseItsLabels() {
            let wikitext = """
                ==English==
                ===Adjective===
                # [[taste|Tasting]] of [[salt]].
                #: {{ux|en|The soup is salty.}}
                # {{lb|en|slang}} [[irritated|Irritated]], [[annoyed]], [[angry]], [[bitter]].
                # {{lb|en|UK|_|mildly|vulgar}} {{l|en|tired|Tired}} or [[exhausted]].
                ==Italian==
                # {{lb|it|vulgar}} what a drag!
                """
            let senses = [
                Wiktionary.Sense(formOf: nil, language: "en", text: "Tasting of salt."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Irritated, annoyed, angry, bitter."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Tired or exhausted."),
                Wiktionary.Sense(formOf: nil, language: "it", text: "What a drag!"),
            ]

            expectNoDifference(
                Wiktionary.labeled(senses, wikitext: wikitext),
                [
                    Wiktionary.Sense(formOf: nil, language: "en", text: "Tasting of salt."),
                    Wiktionary.Sense(
                        formOf: nil,
                        labels: ["slang"],
                        language: "en",
                        text: "Irritated, annoyed, angry, bitter."
                    ),
                    Wiktionary.Sense(
                        formOf: nil,
                        labels: ["UK", "mildly", "vulgar"],
                        language: "en",
                        text: "Tired or exhausted."
                    ),
                    Wiktionary.Sense(formOf: nil, labels: ["vulgar"], language: "it", text: "What a drag!"),
                ]
            )
        }

        @Test
        func theNotesSkipOldAndTechnicalSensesAndKeepTheConversationalOne() async throws {
            let senses = [
                Wiktionary.Sense(formOf: nil, labels: ["obsolete"], language: "en", text: "Pickled."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Tasting of salt."),
                Wiktionary.Sense(formOf: nil, labels: ["linguistics"], language: "en", text: "Of a dialect."),
                Wiktionary.Sense(formOf: nil, language: "en", text: "Containing salt."),
                Wiktionary.Sense(formOf: nil, labels: ["slang"], language: "en", text: "Irritated, annoyed."),
            ]

            let entry = try await Self.entry(senses)

            expectNoDifference(
                entry,
                DictionaryEntry(
                    correctForm: nil, senses: ["Tasting of salt.", "(slang) Irritated, annoyed."], title: "x")
            )
        }

        @Test
        func theNotesKeepAnOldSenseWhenItIsTheOnlyOne() async throws {
            let senses = [Wiktionary.Sense(formOf: nil, labels: ["archaic"], language: "en", text: "Amid.")]

            let entry = try await Self.entry(senses)

            expectNoDifference(
                entry,
                DictionaryEntry(correctForm: nil, senses: ["Amid."], title: "x")
            )
        }

        @Test
        func onlyRegisterAndRegionLabelsAreShown() async throws {
            let labels = ["UK", "Irish", "transitive", "mildly", "Vulgar", "internet slang", "slang", "idiomatic"]

            let entry = try await Self.entry([
                Wiktionary.Sense(formOf: nil, labels: labels, language: "en", text: "Tired.")
            ])

            expectNoDifference(
                entry,
                DictionaryEntry(correctForm: nil, senses: ["(UK, Ireland, vulgar, slang) Tired."], title: "x")
            )
        }

        @Test
        func anUnverifiedSenseIsSkipped() {
            expectNoDifference(
                Wiktionary.sense(fromHTML: "(Can we verify this sense?) To engage in trial and error.", language: "en"),
                nil
            )
        }

        @Test
        func anEntryWithoutEnglishUsesTheFirstLanguageAlphabetically() async throws {
            let senses = [
                Wiktionary.Sense(formOf: nil, language: "it", text: "Italian."),
                Wiktionary.Sense(formOf: nil, language: "es", text: "Spanish."),
            ]

            let entry = try await Self.entry(senses)

            expectNoDifference(
                entry,
                DictionaryEntry(correctForm: nil, senses: ["Spanish."], title: "x")
            )
        }

        @Test
        func theTitleIsEncodedForTheURL() {
            expectNoDifference(Wiktionary.pathComponent(for: "Bob's your uncle"), "Bob%27s_your_uncle")
            expectNoDifference(Wiktionary.pathComponent(for: "and/or"), "and%2For")
        }

        @Test(
            arguments: [
                ("mute point", "a mute point", true),
                ("nur Bahnhof verstehen", "Ich verstehe nur Bahnhof", true),
                ("nip in the butt", "nip it in the butt", true),
                ("fixin", "fixin to", false),
                ("set square", "Trying to square the triangle", false),
                ("once in a purple moon", "one in a blue moon", false),
            ]
        )
        func aSearchResultMustShareMostWordsWithTheTerm(title: String, term: String, isClose: Bool) {
            expectNoDifference(Wiktionary.closestTitles([title], to: term), isClose ? [title] : [])
        }

        @Test
        func theClosestSearchResultComesFirstAndPrefersTheOneInTheTerm() {
            expectNoDifference(
                Wiktionary.closestTitles(
                    ["baby elephant in the room", "elephants in the room", "elephant in the room", "elephant"],
                    to: "the elephant in the room"
                ),
                ["elephant in the room", "elephants in the room", "baby elephant in the room"]
            )
        }

        @Test
        func theLongestPhrasesInsideATermComeFirst() {
            expectNoDifference(
                Wiktionary.phrases(in: "He kicked the bucket"),
                ["kicked the bucket", "he kicked the", "he kicked"]
            )
            expectNoDifference(
                Wiktionary.phrases(in: "we need to touch base"),
                [
                    "need to touch base", "we need to touch", "to touch base", "need to touch", "we need to",
                    "touch base", "to touch", "need to", "we need",
                ]
            )
            expectNoDifference(Wiktionary.phrases(in: "fixin to"), [])
        }

        @Test
        func onlyExistingTitlesAreKeptInOrder() throws {
            let data = Data(
                """
                {"query": {
                    "normalized": [{"from": "bird's_eye view", "to": "bird's eye view"}],
                    "redirects": [{"from": "bird's eye view", "to": "bird's-eye view"}],
                    "pages": [
                        {"title": "to square the circle", "missing": true},
                        {"title": "square the circle", "pageid": 1},
                        {"title": "bird's-eye view", "pageid": 2}
                    ]
                }}
                """
                .utf8
            )
            expectNoDifference(
                try Wiktionary.existingTitles(
                    ["to square the circle", "bird's_eye view", "square the circle", "zzqx"],
                    from: data
                ),
                ["bird's-eye view", "square the circle"]
            )
        }

        private static func entry(_ senses: [Wiktionary.Sense]) async throws -> DictionaryEntry? {
            try await Wiktionary.entry(title: "x", senses: senses) { title in
                Issue.record("Followed the link to \(title)")
                return []
            }
        }
    }
}
