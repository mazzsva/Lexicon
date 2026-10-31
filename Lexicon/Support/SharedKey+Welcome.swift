//
//  SharedKey+Welcome.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 01/10/26.
//

import ComposableArchitecture

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var hasDismissedWelcome: Self {
        Self[.appStorage("hasDismissedWelcome"), default: false]
    }

    #if DEBUG
    static var showsWelcomeAtNextLaunch: Self {
        Self[.appStorage("showsWelcomeAtNextLaunch"), default: false]
    }
    #endif
}
