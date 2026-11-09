//
//  AppPaletteTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 08/11/26.
//

import Foundation
import Testing

@testable import Lexicon

extension BaseSuite {
    @Suite
    struct AppPaletteTests {
        private static let gain = 1.20
        private static let lift = 0.1148

        @Test(arguments: [
            AppPalette.background,
            AppPalette.RGB(red: 0.014, green: 0.072, blue: 0.137),
            AppPalette.RGB(red: 0.147, green: 0.069, blue: 0.004),
            AppPalette.RGB(red: 0.157, green: 0.024, blue: 0.034),
            AppPalette.RGB(red: 0.04, green: 0.10, blue: 0.30),
        ])
        func theSurfaceFollowsTheBackground(background: AppPalette.RGB) {
            let surface = Self.composite(background.surface, over: background)

            #expect(abs(surface.red - Self.target(background.red)) < 0.005)
            #expect(abs(surface.green - Self.target(background.green)) < 0.005)
            #expect(abs(surface.blue - Self.target(background.blue)) < 0.005)
        }

        @Test
        func theSurfaceIsLighterThanTheBackground() {
            let surface = Self.composite(AppPalette.surface, over: AppPalette.background)

            #expect(surface.red > AppPalette.background.red)
            #expect(surface.green > AppPalette.background.green)
            #expect(surface.blue > AppPalette.background.blue)
        }

        @Test
        func whiteTextIsReadableOnTheBackground() {
            let white = AppPalette.RGB(red: 1, green: 1, blue: 1)

            #expect(Self.contrast(white, AppPalette.background) >= 7)
        }

        @Test
        func whiteTextIsReadableOnTheSurface() {
            let white = AppPalette.RGB(red: 1, green: 1, blue: 1)
            let surface = Self.composite(AppPalette.surface, over: AppPalette.background)

            #expect(Self.contrast(white, surface) >= 7)
        }

        @Test
        func theBookmarkIsReadableOnTheSurface() {
            let bookmark = AppPalette.RGB(red: 1, green: 0.576, blue: 0)
            let surface = Self.composite(AppPalette.surface, over: AppPalette.background)

            #expect(Self.contrast(bookmark, surface) >= 4.5)
        }

        private static func target(_ value: Double) -> Double {
            min(1, gain * value + lift)
        }

        private static func composite(_ surface: AppPalette.RGB, over background: AppPalette.RGB) -> AppPalette.RGB {
            let opacity = AppPalette.surfaceOpacity
            return AppPalette.RGB(
                red: (1 - opacity) * background.red + opacity * surface.red,
                green: (1 - opacity) * background.green + opacity * surface.green,
                blue: (1 - opacity) * background.blue + opacity * surface.blue
            )
        }

        private static func luminance(_ color: AppPalette.RGB) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }

        private static func contrast(_ first: AppPalette.RGB, _ second: AppPalette.RGB) -> Double {
            let lighter = max(luminance(first), luminance(second))
            let darker = min(luminance(first), luminance(second))
            return (lighter + 0.05) / (darker + 0.05)
        }
    }
}
