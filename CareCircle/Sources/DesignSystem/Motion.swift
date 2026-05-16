import SwiftUI

/// Motion tokens. Use these instead of bare `.easeOut` /
/// `.linear` so the app speaks one motion language. Every animation
/// site should branch on `@Environment(\.accessibilityReduceMotion)`
/// and fall back to `nil` (no animation) when that's true.
enum Motion {
    /// Default reveal / transition. Slightly damped spring that
    /// settles fast without overshoot.
    static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    /// Quick press feedback for buttons / rows. Snaps back fast.
    static let press: Animation = .spring(response: 0.18, dampingFraction: 0.9)

    /// Card-arrival spring for inbound WebSocket updates. A touch
    /// bouncier so the eye catches the new content.
    static let arrive: Animation = .spring(response: 0.42, dampingFraction: 0.78)

    /// Crossfade for content swaps where a slide would be too loud.
    static let crossfade: Animation = .easeInOut(duration: 0.22)

    /// Per-row delay when staggering reveals. Multiply by index.
    static let staggerStep = 0.04

    /// Helper: returns the animation, or `nil` when Reduce Motion is
    /// on. Use as `.animation(Motion.respecting(reduceMotion, .spring), value: x)`.
    static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}
