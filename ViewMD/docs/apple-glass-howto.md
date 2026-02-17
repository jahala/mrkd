# Apple Liquid Glass - Complete Implementation Guide

A comprehensive reference for implementing Liquid Glass effects in macOS 26 / iOS 26 SwiftUI apps.

**Platforms:** iOS 26.0+, iPadOS 26.0+, macOS 26.0+, Mac Catalyst 26.0+, tvOS 26.0+, watchOS 26.0+

---

## Overview

Liquid Glass is a dynamic material that:
- Blurs content behind it
- Reflects color and light of surrounding content
- Reacts to touch and pointer interactions in real time

Standard SwiftUI components use Liquid Glass automatically. For custom components, use the APIs below.

---

## 1. The Glass Structure

Defines the configuration of the Liquid Glass material.

### Static Variants

| Variant | Description | Use Case |
|---------|-------------|----------|
| `.regular` | Standard glass with blur and dimming | Default, most UI elements |
| `.clear` | Minimal blur, no dimming | Over media-rich content (photos, videos) |
| `.identity` | No effect applied | Accessibility fallback |

### Instance Methods

```swift
// Make glass respond to touch/pointer interactions
func interactive(_ isEnabled: Bool = true) -> Glass

// Apply a tint color to the glass
func tint(_ color: Color?) -> Glass
```

### Usage Examples

```swift
// Regular glass (default)
.glassEffect()
.glassEffect(.regular)

// Clear glass for media backgrounds
.glassEffect(.clear)

// With tint color
.glassEffect(.regular.tint(.blue))

// Interactive (responds to touch/hover)
.glassEffect(.regular.interactive())

// Chained modifiers (order doesn't matter)
.glassEffect(.regular.tint(.orange).interactive())
.glassEffect(.clear.interactive().tint(.blue))
```

### When to Use Each Variant

**`.regular`** (default)
- Standard UI controls and panels
- Navigation elements
- Applies a dimming layer to background

**`.clear`** - Use when ALL THREE conditions are met:
1. Element sits over media-rich content (photos, videos)
2. Background content won't be negatively affected by dimming
3. Content above glass is bold and bright

**`.identity`**
- When user has Reduce Transparency accessibility setting enabled
- Fallback for performance-constrained situations

**Critical Rule:** Never mix `.regular` and `.clear` in the same interface group.

---

## 2. Applying Glass to Views

### glassEffect(_:in:) Modifier

```swift
func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()  // Capsule
) -> some View
```

### Basic Examples

```swift
// Default: regular glass in capsule shape
Text("Hello")
    .padding()
    .glassEffect()

// Custom shape with corner radius
Text("Hello")
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16))

// Clear variant with custom shape
Text("Hello")
    .padding()
    .glassEffect(.clear, in: .rect(cornerRadius: 16))

// Tinted and interactive
Text("Hello")
    .padding()
    .glassEffect(.regular.tint(.orange).interactive())
```

### Available Shapes

```swift
.glassEffect(in: .capsule)                           // Default
.glassEffect(in: .circle)
.glassEffect(in: .rect(cornerRadius: 16))
.glassEffect(in: .ellipse)
.glassEffect(in: RoundedRectangle(cornerRadius: 16))
.glassEffect(in: .rect(cornerRadius: .containerConcentric))  // Matches container
```

### Important Notes

- Glass anchors to the view's bounds, **including padding**
- Apply `.glassEffect()` **after** other appearance modifiers
- The glass effect captures content to render in the container

---

## 3. Button Styles

Use these instead of custom glass effects for buttons.

### Available Styles

```swift
// Standard glass button
.buttonStyle(.glass)

// Prominent/emphasized glass button
.buttonStyle(.glassProminent)

// Parameterized with Glass variant
.buttonStyle(.glass(.clear))      // Clear glass for media backgrounds
.buttonStyle(.glass(.regular))    // Explicit regular
```

### Examples

```swift
// Standard glass button
Button("Save") { }
    .buttonStyle(.glass)

// Prominent button with tint
Button("Submit") { }
    .buttonStyle(.glassProminent)
    .tint(.blue)

// Clear glass over photo/video
Button("Edit") { }
    .buttonStyle(.glass(.clear))
```

### Border Shapes

```swift
.buttonBorderShape(.capsule)
.buttonBorderShape(.circle)
.buttonBorderShape(.roundedRectangle(radius: 8))
```

### Control Sizes

```swift
.controlSize(.mini)
.controlSize(.small)
.controlSize(.regular)
.controlSize(.large)
.controlSize(.extraLarge)
```

---

## 4. GlassEffectContainer

Combines multiple Liquid Glass shapes for better performance and morphing animations.

### Why Use It?

1. **Performance**: Consolidates rendering (3 textures → 1)
2. **Morphing**: Shapes can blend and morph into each other
3. **Consistency**: Glass cannot sample other glass, so grouping prevents visual artifacts

### Initializer

```swift
GlassEffectContainer(spacing: CGFloat? = nil) {
    // Content with glass effects
}
```

### Spacing Behavior

The `spacing` parameter controls when glass shapes blend together:
- **Larger spacing**: Shapes blend sooner as they approach each other
- **Spacing > interior layout spacing**: Shapes blend even at rest
- **Equal spacing**: Shapes morph during transitions only

### Example

```swift
GlassEffectContainer(spacing: 40) {
    HStack(spacing: 40) {
        Image(systemName: "pencil")
            .frame(width: 80, height: 80)
            .glassEffect()

        Image(systemName: "eraser")
            .frame(width: 80, height: 80)
            .glassEffect()
    }
}
```

---

## 5. Morphing and Transitions

### glassEffectID(_:in:)

Associates an identity for coordinated transitions between glass elements.

```swift
func glassEffectID(
    _ id: (some Hashable & Sendable)?,
    in namespace: Namespace.ID
) -> some View
```

### GlassEffectTransition

Describes changes when glass effects are added/removed.

| Transition | Description |
|------------|-------------|
| `.identity` | No changes applied |
| `.matchedGeometry` | Coordinates geometry changes across matched views |
| `.materialize` | Fades content, animates glass material, no geometry matching |

### Complete Morphing Example

```swift
@State private var isExpanded = false
@Namespace private var namespace

var body: some View {
    GlassEffectContainer(spacing: 40) {
        HStack(spacing: 40) {
            Image(systemName: "scribble.variable")
                .frame(width: 80, height: 80)
                .glassEffect()
                .glassEffectID("pencil", in: namespace)

            if isExpanded {
                Image(systemName: "eraser.fill")
                    .frame(width: 80, height: 80)
                    .glassEffect()
                    .glassEffectID("eraser", in: namespace)
            }
        }
    }

    Button("Toggle") {
        withAnimation {
            isExpanded.toggle()
        }
    }
    .buttonStyle(.glass)
}
```

---

## 6. glassEffectUnion

Combines multiple views into a single unified glass shape.

```swift
func glassEffectUnion(
    id: (some Hashable & Sendable)?,
    namespace: Namespace.ID
) -> some View
```

### Example: Grouped Icons

```swift
@Namespace var namespace
let symbols = ["cloud.bolt.rain.fill", "sun.rain.fill", "moon.stars.fill", "moon.fill"]

GlassEffectContainer(spacing: 20) {
    HStack(spacing: 20) {
        ForEach(symbols.indices, id: \.self) { i in
            Image(systemName: symbols[i])
                .frame(width: 80, height: 80)
                .glassEffect()
                .glassEffectUnion(id: i < 2 ? "weather" : "night", namespace: namespace)
        }
    }
}
// First two icons share one glass shape, last two share another
```

---

## 7. Accessibility

### Reduce Transparency Support

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

Text("Content")
    .padding()
    .glassEffect(reduceTransparency ? .identity : .regular)
```

### Reduce Motion Support

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// Disable morphing animations if reduce motion is on
```

---

## 8. Backward Compatibility

### Extension Pattern

```swift
extension View {
    @ViewBuilder
    func glassedEffect(
        _ glass: Glass = .regular,
        in shape: some Shape = Capsule(),
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            let g = interactive ? glass.interactive() : glass
            self.glassEffect(g, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
}
```

---

## 9. Performance Best Practices

1. **Limit glass effects**: Don't overuse - each effect requires rendering resources
2. **Use GlassEffectContainer**: Always wrap multiple glass elements
3. **Profile with Instruments**: Check for UI hitches
4. **Test on real devices**: Performance varies by hardware

---

## 10. Common Patterns

### Floating Action Button

```swift
Button {
    // action
} label: {
    Image(systemName: "plus")
        .font(.title2.bold())
        .frame(width: 56, height: 56)
}
.buttonStyle(.glassProminent)
.buttonBorderShape(.circle)
.tint(.blue)
```

### Toolbar with Glass

```swift
NavigationStack {
    ContentView()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Draw", systemImage: "pencil") { }
                Button("Erase", systemImage: "eraser") { }
            }
        }
}
```

### Custom Panel Over Image

```swift
// For content over media-rich backgrounds
ZStack {
    Image("background")

    VStack {
        // Controls
    }
    .padding()
    .glassEffect(.clear, in: .rect(cornerRadius: 16))
}
```

---

## Quick Reference

| Task | Code |
|------|------|
| Basic glass | `.glassEffect()` |
| Custom shape | `.glassEffect(in: .rect(cornerRadius: 16))` |
| Over photos/video | `.glassEffect(.clear)` |
| Interactive | `.glassEffect(.regular.interactive())` |
| Tinted | `.glassEffect(.regular.tint(.blue))` |
| Glass button | `.buttonStyle(.glass)` |
| Prominent button | `.buttonStyle(.glassProminent)` |
| Clear glass button | `.buttonStyle(.glass(.clear))` |
| Multiple effects | `GlassEffectContainer { ... }` |
| Morphing | `.glassEffectID("id", in: namespace)` |
| Unified shape | `.glassEffectUnion(id: "group", namespace: namespace)` |

---

## 11. Landmarks Sample App Patterns

The official Landmarks sample app demonstrates key Liquid Glass patterns:

### Background Extension Effect
Extend and blur images behind sidebars/inspectors:
```swift
Image("landmark")
    .backgroundExtensionEffect()
```

### Toolbar Organization
Group related toolbar buttons together - the system applies Liquid Glass automatically:
```swift
.toolbar {
    ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Share", systemImage: "square.and.arrow.up") { }
        Button("Favorite", systemImage: "heart") { }
    }
    ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Collections", systemImage: "folder") { }
        Button("Inspector", systemImage: "sidebar.right") { }
    }
}
```

### Custom Badge with Glass
```swift
GlassEffectContainer {
    ForEach(badges) { badge in
        Image(systemName: badge.symbol)
            .frame(width: 60, height: 60)
            .background {
                Hexagon()
                    .glassEffect()
            }
            .glassEffectID(badge.id, in: namespace)
    }
}
```

---

## Resources

### Apple Documentation
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- [WWDC25: Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Adopting Liquid Glass (HIG)](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)

### Reading Apple Docs Without JavaScript

Apple's documentation requires JavaScript to render. To read it programmatically (e.g., with curl, WebFetch, or AI tools), use **sosumi.ai** as a proxy:

```
# Apple URL:
https://developer.apple.com/documentation/swiftui/glass

# Sosumi equivalent (works without JavaScript):
https://sosumi.ai/documentation/swiftui/glass
```

Pattern: Replace `developer.apple.com` with `sosumi.ai`

---

*Document Version: 1.2 | Last Updated: January 2026*
