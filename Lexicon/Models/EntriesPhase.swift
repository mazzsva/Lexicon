//
//  EntriesPhase.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 11/10/26.
//

import CasePaths
import IdentifiedCollections

@CasePathable
@dynamicMemberLookup
enum EntriesPhase: Equatable {
    case failed
    case loaded(IdentifiedArrayOf<Entry>)
    case loading
}
