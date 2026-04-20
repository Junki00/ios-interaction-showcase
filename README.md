# iOS Interaction Showcase

Code excerpts from **[Hydro Paint](https://apps.apple.com/app/hydro-paint-water-tracker/id6761187262)**, a hydration-tracking iOS app built with SwiftUI.
These files highlight interaction design, design-system architecture, and Metal shader work.

> The full app is not open-source. This repository contains curated standalone snippets
> for reference and portfolio purposes. Some files depend on app-specific types
> (`PondaViewModel`, `PondaItem`, etc.) and are not independently compilable.

## Demo: Click the gif to watch the full demo on YouTube.

<p>
  <a href="https://www.youtube.com/watch?v=wUlWzYwC7Es">
    <img src="https://github.com/user-attachments/assets/09566957-b72c-4718-9857-2e0b9da8874e" alt="Hydro Paint Demo" width="280">
  </a>
</p>

## About Hydro Paint
A hydration-tracking app that maps daily water intake to the gradual reveal of ukiyo-e layered landscapes.

A drag-based entry mechanic designed for mobile builds muscle memory and tactile feel. The goal is to make a health habit feel like uncovering a painting, not filling a progress bar.

## Engineering Decisions

Three product and engineering tradeoffs behind the current V1.

### 1. Shipping V1: food tracker → water tracker

**Problem.** The original concept was a full food tracker with a pantry view, CRUD meal logging, and a data dashboard. The priority wasn't in generic CRUD screens — too many apps already offer that.

**Decision.** Cut food logging entirely. Keep only the core loop that no other app has: drink water → reveal ukiyo-e layers. This let me spend time on interaction quality (radial menu, Metal shaders, haptic mapping) and forming the product's core logic chain, with plans to expand into food tracking in the future.

**Why.** A food tracker with average interactions ships into a crowded market and says nothing. A water tracker with a unique visual and gestural identity is a smaller product but a stronger portfolio piece — and a better foundation to expand from.

**Outcome.** App Store published. The food tracking architecture still exists on the main branch of the private repo as a reference for future iterations.

### 2. Removing the swipe-up drawer

**Problem.** Early builds had a data dashboard placed beneath the main view in a ZStack, accessible via swipe-up. It worked in isolation.

**Decision.** Removed the drawer entirely. Replaced it with a button on the home screen that presents the data panel as a modal.

**Why.** The gallery view and the main view are visually similar — both show ukiyo-e artwork. Users instinctively tried to swipe up on the gallery too, expecting a drawer that wasn't there. Same gesture, similar-looking screens, different behavior — this is a gesture semantic conflict. Rather than add conditional swipe handling (which would still feel inconsistent), I removed the gesture entirely and moved the entry point to an explicit button. Less elegant, more predictable.

> Early drawer version:
<img src="https://github.com/user-attachments/assets/eff45445-73f8-4b35-84d3-4d335c2414cd" alt="Early drawer version" width="280" />

### 3. Radial menu: from distance threshold to long-press lock

**Problem.** After satellites fan out, the closest one becomes "activated" — it scales up and plays an escape animation in real time based on finger distance. Only one satellite is activated at a time. When the finger catches up to an activated satellite, it becomes "selected"; holding the selected state for 0.4s locks it and enters vertical-slide adjustment mode.

The first implementation used a distance threshold to determine lock state. In practice, micro-movements caused the adjustment slider to repeatedly appear and disappear — the finger kept crossing the threshold back and forth.

**Decision.** Replaced distance-based lock detection with a deliberate 0.4s hold requirement: the satellite must remain selected (finger has caught up to it) for 0.4s before locking. This turns an ambiguous distance check into an intentional time-based confirmation.

**Why.** Two separate fixes addressed two separate problems:

- **Lock chattering → time-based confirmation.** Distance thresholds assume a steady finger. A 0.4s hold absorbs micro-movements without adding UI complexity.
- **Escape animation overshoot → sin(π/2·t) velocity curve.** The original spring animation still had velocity when the satellite reached its target position, so the satellite kept overshooting — the finger could never catch up at a predictable distance. Replacing it with sin(π/2·t) ease-out brings velocity to zero at the target, making the "catch-up" point consistent and reliable.

**Outcome.** Open and lock events each fire a Metal shader ripple synced with semantically mapped haptic feedback. See [`RadialMenu/`](#code-contents) for the final implementation.

> Early radial menu design (Figma): 
<img src="https://github.com/user-attachments/assets/f38365de-1af8-4cd4-aa0a-612792fd5820" alt="Early radial menu design in Figma" width="100%" />

## Code Contents

### [`DesignSystem/`](./DesignSystem)

Centralized design tokens — colors, spacing, typography, dual-layer shadows,
spring animations, and a haptic-feedback semantic policy.

Highlights:
- **Haptics semantic mapping table** — maps every interaction intent (navigation, selection, confirmation, cancellation, milestone) to a specific `UIFeedbackGenerator` type, enforcing consistency across the entire app.
- **iOS 26 Liquid Glass graceful degradation** — `stageButton()` and `glassCircle()` modifiers that use Liquid Glass on iOS 26 and fall back to solid capsule/circle styles on older systems.
- **Weight-based animation tiers** — `snappy` / `fluid` / `heavy` springs categorized by perceived physical weight, not by screen.

### [`RadialMenu/`](./RadialMenu)
A custom radial fan menu driven entirely by a single `DragGesture`.
Gesture flow:

1. Tap → present manual-add sheet
2. Long-press (0.4 s) → fan out 4 satellite buttons with a Metal ripple burst
3. Drag → the nearest satellite becomes "activated" (scaled up + escape animation). Only one satellite is activated at a time; activation follows finger position in real time via sin(π/2·t) ease-out
4. Finger catches up to activated satellite → "selected". Hold selected state for 0.4 s → lock with a second Metal ripple, enter adjusting mode
5. Slide vertically → multiplier adjustment in ×0.5 steps
6. Slide horizontally → cancel gesture
7. Release → confirm entry or cancel

Key implementation details:
- State machine: `idle → pressing → open → adjusting(slot)`
- Proximity factor uses `sin(π/2 · t)` ease-out, not linear interpolation
- Metal shader ripple on both open and lock events, synced with haptic feedback
- Full `accessibilityLabel` / `accessibilityHidden` coverage

### [`Shaders/`](./Shaders)

Metal shaders for the ripple distortion effect, presented as a learning progression:

| Shader | What it adds |
|--------|-------------|
| `rippleStep2` | Basic expanding ring displacement |
| `rippleStep3` | Cosine envelope for smooth edges |
| `rippleStep4` | Distance-based energy decay |
| `rippleStep5` | Multiple concentric wavefronts |
| `rippleStep6` | Production guards (NaN safety, elapsed bounds) |
| **`rippleColorBurst`** | Production shader used in the radial menu |

`rippleColorBurst` is used as a SwiftUI `.layerEffect` and fires on both menu open and satellite lock events.

## Tech Stack

- SwiftUI (iOS 17–26)
- Metal / SwiftUI Shader integration (`ShaderLibrary`, `.visualEffect`, `.layerEffect`)
- iOS 26 Liquid Glass (`.glassEffect`, `.buttonStyle(.glass(...))`)
- Swift Concurrency (`async/await` for gesture timers)

## License

These code excerpts are provided for reference and portfolio purposes.
All rights reserved. Not licensed for redistribution or commercial use.
