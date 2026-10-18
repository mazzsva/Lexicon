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

    nonisolated static let completionDuration: Double = 0.9
    static let earliestCompletion: Double = 1.1

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
            .float(dark),
            .float(mirrored),
            .floatArray(pulses)
        )
    }
}
