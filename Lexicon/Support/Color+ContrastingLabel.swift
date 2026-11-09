//
//  Color+ContrastingLabel.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 08/11/26.
//

import SwiftUI

extension Color.Resolved {
    var contrastingLabel: Color {
        relativeLuminance > Self.balancedLuminance ? .black : .white
    }

    var relativeLuminance: Double {
        0.2126 * Double(linearRed) + 0.7152 * Double(linearGreen) + 0.0722 * Double(linearBlue)
    }

    private static let balancedLuminance = 0.179
}
