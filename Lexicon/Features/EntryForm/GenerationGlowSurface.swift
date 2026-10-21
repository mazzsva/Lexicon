//
//  GenerationGlowSurface.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 18/10/26.
//

import SwiftUI

struct GenerationGlowSurface: View {
    let completion: Double?
    let pulses: [Double]
    let time: Double
    let writingStart: Double?

    nonisolated static let completionDuration: Double = 0.7
    nonisolated static let earliestCompletion: Double = 1.0
    nonisolated static let homeArrival: Double = 0.72

    nonisolated private static let cornerRadius: Float = 26
    private static let unset: Float = 1e6

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let time = Float(time)
        let writingStart = writingStart.map(Float.init) ?? Self.unset
        let completion = completion.map(Float.init) ?? Self.unset
        let dark: Float = colorScheme == .dark ? 1 : 0
        let mirrored: Float = layoutDirection == .rightToLeft ? 1 : 0
        let pulses = pulses.map(Float.init)
        Rectangle()
            .visualEffect { content, proxy in
                content.colorEffect(
                    Self.shader(
                        size: proxy.size,
                        time: time,
                        writingStart: writingStart,
                        completion: completion,
                        dark: dark,
                        mirrored: mirrored,
                        pulses: pulses
                    )
                )
            }
    }

    static func palette(for colorScheme: ColorScheme) -> [Color] {
        colorScheme == .dark
            ? [
                Color(red: 0.30, green: 0.78, blue: 1.00),
                Color(red: 0.33, green: 0.50, blue: 1.00),
                Color(red: 0.66, green: 0.40, blue: 1.00),
                Color(red: 1.00, green: 0.36, blue: 0.78),
                Color(red: 1.00, green: 0.47, blue: 0.42),
                Color(red: 1.00, green: 0.70, blue: 0.32),
                Color(red: 1.00, green: 0.82, blue: 0.24),
            ]
            : [
                Color(red: 0.22, green: 0.62, blue: 1.00),
                Color(red: 0.18, green: 0.40, blue: 1.00),
                Color(red: 0.55, green: 0.30, blue: 1.00),
                Color(red: 0.95, green: 0.24, blue: 0.62),
                Color(red: 1.00, green: 0.40, blue: 0.32),
                Color(red: 1.00, green: 0.62, blue: 0.30),
                Color(red: 1.00, green: 0.74, blue: 0.16),
            ]
    }

    nonisolated private static func shader(
        size: CGSize,
        time: Float,
        writingStart: Float,
        completion: Float,
        dark: Float,
        mirrored: Float,
        pulses: [Float]
    ) -> Shader {
        ShaderLibrary.default.generationGlow(
            .float2(size),
            .float(cornerRadius),
            .float(time),
            .float(writingStart),
            .float(completion),
            .float(Float(completionDuration)),
            .float(Float(homeArrival)),
            .float(dark),
            .float(mirrored),
            .floatArray(pulses)
        )
    }
}
