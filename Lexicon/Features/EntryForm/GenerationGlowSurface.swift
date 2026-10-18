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

    static let completionDuration: Double = 0.9
    static let earliestCompletion: Double = 1.1

    private static let cornerRadius: Float = 26

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let cornerRadius = Self.cornerRadius
        let completionDuration = Float(Self.completionDuration)
        let time = Float(time)
        let writingStart = Float(writingStart ?? 1e6)
        let completion = Float(completion ?? 1e6)
        let dark: Float = colorScheme == .dark ? 1 : 0
        let mirrored: Float = layoutDirection == .rightToLeft ? 1 : 0
        let pulses = pulses.map(Float.init)
        Rectangle()
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.default.generationGlow(
                        .float2(proxy.size),
                        .float(cornerRadius),
                        .float(time),
                        .float(writingStart),
                        .float(completion),
                        .float(completionDuration),
                        .float(dark),
                        .float(mirrored),
                        .floatArray(pulses)
                    )
                )
            }
    }
}
