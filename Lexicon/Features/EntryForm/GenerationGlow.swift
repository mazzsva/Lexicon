//
//  GenerationGlow.swift
//  Lexicon
//
//  Created by Lorenzo Mazzarotto on 18/10/26.
//

import ComposableArchitecture
import SwiftUI

struct GenerationGlow: View {
    let completedGenerationCount: Int
    let definition: String
    let generation: EntryForm.Generation?

    private static let maximumPulseCount = 8
    private static let minimumPulseInterval = 0.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var run: Run?

    var body: some View {
        Color(.secondarySystemGroupedBackground)
            .overlay {
                if let run {
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        if reduceMotion {
                            GenerationGlowSurface(completion: nil, pulses: [], time: 3, writingStart: 0)
                        } else {
                            GenerationGlowSurface(
                                completion: run.completion,
                                pulses: run.pulses,
                                time: context.date.timeIntervalSince(run.start),
                                writingStart: run.writingStart
                            )
                        }
                    }
                    .id(run.start)
                    .transition(.asymmetric(insertion: reduceMotion ? .opacity : .identity, removal: .opacity))
                } else {
                    GenerationGlowSurface(completion: nil, pulses: [], time: 0, writingStart: nil)
                }
            }
            .onChange(of: generation) { generationChanged() }
            .onChange(of: definition) { definitionChanged() }
            .onChange(of: reduceMotion) { reduceMotionChanged() }
            .task(id: run?.completion) { await completionChanged() }
    }

    private var isCompleted: Bool {
        run.map { $0.completedGenerationCount != completedGenerationCount } ?? false
    }

    private func completionChanged() async {
        guard let run, let completion = run.completion else { return }
        let end = completion + GenerationGlowSurface.completionDuration
        try? await Task.sleep(for: .seconds(end - run.elapsedTime))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.4)) { self.run = nil }
    }

    private func definitionChanged() {
        guard generation.is(\.writing), var run else { return }
        let time = run.elapsedTime
        guard run.pulses.last.map({ time - $0 >= Self.minimumPulseInterval }) ?? true else { return }
        run.pulses = run.pulses.suffix(Self.maximumPulseCount - 1) + [time]
        self.run = run
    }

    private func generationChanged() {
        switch generation {
        case .lookingUp:
            withAnimation(.easeInOut(duration: 0.4)) { run = Run(completedGenerationCount: completedGenerationCount) }
        case .writing where run == nil:
            run = Run(completedGenerationCount: completedGenerationCount, writingStart: 0)
        case .writing:
            run?.writingStart = run?.elapsedTime
        case nil where isCompleted && !reduceMotion:
            run?.completion = run.map { max($0.elapsedTime, GenerationGlowSurface.earliestCompletion) }
        case nil, .failed:
            withAnimation(.easeInOut(duration: 0.4)) { run = nil }
        }
    }

    private func reduceMotionChanged() {
        guard reduceMotion, run?.completion != nil else { return }
        withAnimation(.easeInOut(duration: 0.4)) { run = nil }
    }
}

extension GenerationGlow {
    private struct Run {
        let completedGenerationCount: Int
        var completion: Double?
        var pulses: [Double] = []
        let start = Date.now
        var writingStart: Double?

        var elapsedTime: Double {
            Date.now.timeIntervalSince(start)
        }
    }
}
