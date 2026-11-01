//
//  BaseSuite.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 09/09/26.
//

import Dependencies
import DependenciesTestSupport
import Foundation
import Testing

@Suite(
    .serialized,
    .dependencies { $0.locale = Locale(identifier: "en_US") }
)
struct BaseSuite {}
