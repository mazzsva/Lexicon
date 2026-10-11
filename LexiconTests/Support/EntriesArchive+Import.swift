//
//  EntriesArchive+Import.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import Dependencies
import Foundation

@testable import Lexicon

extension EntriesArchive.Import {
    init(duplicateCount: Int, entries: [Entry], invalidCount: Int) {
        self.init(records: [], existing: [], now: Date(timeIntervalSince1970: 0), uuid: { UUID(0) })
        self.duplicateCount = duplicateCount
        self.entries = entries
        self.invalidCount = invalidCount
    }
}
