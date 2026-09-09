//
//  LoadingWindowTests.swift
//  LexiconTests
//
//  Created by Lorenzo Mazzarotto on 09/09/26.
//

import SwiftUI
import Testing
import UIKit

@testable import Lexicon

extension BaseSuite {
    @Suite(.serialized)
    @MainActor
    struct LoadingWindowTests {
        // An anchor outside the hierarchy has no scene to put the window in
        @Test
        func theLoadingWindowWaitsForAScene() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let anchor = LoadingWindowAnchor()

            anchor.isLoadingVisible = true

            expectNoLoadingWindow(in: scene)
        }

        // Moving into a window is the first moment the anchor can reach a scene
        @Test
        func theLoadingWindowAppearsOnceTheAnchorJoinsAScene() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let anchor = LoadingWindowAnchor()
            anchor.isLoadingVisible = true
            expectNoLoadingWindow(in: scene)

            let host = makeHost(in: scene)
            host.addSubview(anchor)

            await wait(until: { loadingWindow(in: scene) != nil })
            #expect(loadingWindow(in: scene) != nil)
            await hide(anchor, in: scene)
        }

        // The window sits one level above the app so it covers whatever the app shows
        @Test
        func theLoadingWindowCoversTheAppWhileItLoads() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let anchor = attachedAnchor(in: scene)

            anchor.isLoadingVisible = true

            let window = try #require(loadingWindow(in: scene))
            #expect(window.windowLevel == UIWindow.Level(UIWindow.Level.normal.rawValue + 1))
            #expect(window.isUserInteractionEnabled)
            await wait(until: { window.alpha == 1 })
            #expect(window.alpha == 1)
            await hide(anchor, in: scene)
        }

        // The hosting controller outlives each message, so a new one has to be pushed into it
        @Test
        func theMessageReachesThePresentedWindow() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let anchor = attachedAnchor(in: scene)

            anchor.message = "Signing in…"
            anchor.isLoadingVisible = true
            #expect(presentedMessage(in: scene) == "Signing in…")

            anchor.message = "Deleting your account…"
            #expect(presentedMessage(in: scene) == "Deleting your account…")
            await hide(anchor, in: scene)
        }

        // The window leaves the screen only once the fade finishes
        @Test
        func theLoadingWindowFadesAwayWhenTheLoadingEnds() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let anchor = attachedAnchor(in: scene)
            anchor.isLoadingVisible = true
            let window = try #require(loadingWindow(in: scene))

            anchor.isLoadingVisible = false

            #expect(!window.isUserInteractionEnabled)
            await wait(until: { window.isHidden })
            #expect(window.isHidden)
            expectNoLoadingWindow(in: scene)
        }

        // The fade completion must not tear down a window the app asked for again
        @Test
        func aLoadingWindowThatReturnsBeforeTheFadeEndsIsReused() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let anchor = attachedAnchor(in: scene)
            anchor.isLoadingVisible = true
            let window = try #require(loadingWindow(in: scene))

            anchor.isLoadingVisible = false
            anchor.isLoadingVisible = true

            await settle()
            #expect(loadingWindow(in: scene) === window)
            #expect(window.isUserInteractionEnabled)
            await hide(anchor, in: scene)
        }

        private func attachedAnchor(in scene: UIWindowScene) -> LoadingWindowAnchor {
            let anchor = LoadingWindowAnchor()
            makeHost(in: scene).addSubview(anchor)
            return anchor
        }

        private func expectNoLoadingWindow(
            in scene: UIWindowScene,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            #expect(loadingWindow(in: scene) == nil, sourceLocation: sourceLocation)
        }

        private func hide(_ anchor: LoadingWindowAnchor, in scene: UIWindowScene) async {
            anchor.isLoadingVisible = false
            await wait(until: { loadingWindow(in: scene) == nil })
        }

        private func loadingWindow(in scene: UIWindowScene) -> UIWindow? {
            scene.windows.first {
                !$0.isHidden && $0.rootViewController is UIHostingController<LoadingView>
            }
        }

        private func makeHost(in scene: UIWindowScene) -> UIWindow {
            let host = UIWindow(windowScene: scene)
            host.isHidden = false
            return host
        }

        private func presentedMessage(in scene: UIWindowScene) -> String? {
            let controller = loadingWindow(in: scene)?.rootViewController
            return (controller as? UIHostingController<LoadingView>)?.rootView.message
        }

        private func settle() async {
            try? await Task.sleep(for: .milliseconds(500))
        }

        private func wait(until condition: () -> Bool) async {
            for _ in 0 ..< 200 {
                if condition() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }
}
