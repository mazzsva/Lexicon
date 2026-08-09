//
//  Logger+AppSubsystem.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import os

extension Logger {
    static let appSubsystem = "com.mazzsva.Lexicon"

    init(category: String) {
        self.init(subsystem: Self.appSubsystem, category: category)
    }
}
