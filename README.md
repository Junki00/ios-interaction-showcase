# ponda — Selected Code Showcase

Code excerpts from **ponda**, a hydration-tracking iOS app built with SwiftUI.
These files highlight interaction design, design-system architecture, and Metal shader work.

> The full app is not open-source. This repository contains curated standalone snippets
> for reference and portfolio purposes. Some files depend on app-specific types
> (`PondaViewModel`, `PondaItem`, etc.) and are not independently compilable.

## Contents

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
1. **Tap** → present manual-add sheet
2. **Long-press** (0.4 s) → fan out 4 satellite buttons with a Metal ripple burst
3. **Drag to hover** → proximity-based scale with sinusoidal ease-out and haptic ticks
4. **Hover & hold** (0.4 s) → lock satellite, enter adjusting mode with a second ripple
5. **Slide vertically** → multiplier adjustment in ×0.5 steps
6. **Slide horizontally** → cancel gesture
7. **Release** → confirm entry or cancel

Key implementation details:
- State machine: `idle → pressing → open → adjusting(slot)`
- Proximity factor uses `sin(π/2 · t)` ease-out, not linear interpolation
- Two independent `TimelineView`-driven Metal ripple layers (open + lock) with mutual suppression
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
| **`rippleColorBurst`** | Final production shader — chromatic dispersion, spring ease-out, accent-color glow |

`rippleColorBurst` is used as a SwiftUI `.layerEffect` and fires on both menu open and satellite lock events.

## Tech Stack

- SwiftUI (iOS 17–26)
- Metal / SwiftUI Shader integration (`ShaderLibrary`, `.visualEffect`, `.layerEffect`)
- iOS 26 Liquid Glass (`.glassEffect`, `.buttonStyle(.glass(...))`)
- Swift Concurrency (`async/await` for gesture timers)

## License

These code excerpts are provided for reference and portfolio purposes.
All rights reserved. Not licensed for redistribution or commercial use.
