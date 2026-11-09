//
//  View+GroupedBackground.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 17/07/26.
//

import SwiftUI

extension View {
    func groupedBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }
}

extension Color {
    static let appBackground = Color(AppPalette.background)
    static let appSurface = Color(AppPalette.surface).opacity(AppPalette.surfaceOpacity)
}

enum AppPalette {
    static let background = RGB(red: 0.022, green: 0.063, blue: 0.039)
    static let surfaceOpacity = 0.4
    static let surface = background.surface

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        private static let gain = 1.20
        private static let lift = 0.1148

        var surface: RGB {
            func overlay(_ value: Double) -> Double {
                let target = min(1, Self.gain * value + Self.lift)
                let opacity = AppPalette.surfaceOpacity
                return min(1, max(0, (target - (1 - opacity) * value) / opacity))
            }
            return RGB(red: overlay(red), green: overlay(green), blue: overlay(blue))
        }
    }
}

extension Color {
    fileprivate init(_ rgb: AppPalette.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview("Light") {
    Color.clear.groupedBackground()
}

#Preview("Dark AX3") {
    Color.clear
        .groupedBackground()
        .dynamicTypeSize(.accessibility3)
}
