//
//  ContrastingLabelTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 08/11/26.
//

import SwiftUI
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct ContrastingLabelTests {
        @Test(arguments: [
            (Color.white, Color.black),
            (Color(red: 1, green: 0.576, blue: 0), Color.black),
            (Color(red: 0.9, green: 0.9, blue: 0.4), Color.black),
            (Color.black, Color.white),
            (Color(red: 0.02, green: 0.14, blue: 0.08), Color.white),
            (Color(red: 0.04, green: 0.10, blue: 0.30), Color.white),
        ])
        func theLabelContrastsWithTheTint(tint: Color, label: Color) {
            let resolved = tint.resolve(in: EnvironmentValues())

            #expect(resolved.contrastingLabel == label)
        }
    }
}
