//
//  SessionOrigin.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 02/10/26.
//

import CasePaths

@CasePathable
enum SessionOrigin: Equatable {
    case freshSignIn
    case restored
}
