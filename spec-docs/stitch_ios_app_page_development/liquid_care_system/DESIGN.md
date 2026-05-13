---
name: Liquid Care System
colors:
  surface: '#faf9f7'
  surface-dim: '#dadad8'
  surface-bright: '#faf9f7'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f4f1'
  surface-container: '#eeeeeb'
  surface-container-high: '#e8e8e6'
  surface-container-highest: '#e3e3e0'
  on-surface: '#1a1c1b'
  on-surface-variant: '#414845'
  inverse-surface: '#2f312f'
  inverse-on-surface: '#f1f1ee'
  outline: '#717974'
  outline-variant: '#c1c8c3'
  surface-tint: '#436558'
  primary: '#416355'
  on-primary: '#ffffff'
  primary-container: '#597c6d'
  on-primary-container: '#f5fff8'
  inverse-primary: '#aacfbe'
  secondary: '#516072'
  on-secondary: '#ffffff'
  secondary-container: '#d1e1f7'
  on-secondary-container: '#556476'
  tertiary: '#79542b'
  on-tertiary: '#ffffff'
  tertiary-container: '#956d40'
  on-tertiary-container: '#fffbff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#c5ebd9'
  primary-fixed-dim: '#aacfbe'
  on-primary-fixed: '#002117'
  on-primary-fixed-variant: '#2c4d40'
  secondary-fixed: '#d4e4f9'
  secondary-fixed-dim: '#b8c8dd'
  on-secondary-fixed: '#0d1d2c'
  on-secondary-fixed-variant: '#394859'
  tertiary-fixed: '#ffdcbc'
  tertiary-fixed-dim: '#efbd8a'
  on-tertiary-fixed: '#2c1700'
  on-tertiary-fixed-variant: '#614018'
  background: '#faf9f7'
  on-background: '#1a1c1b'
  surface-variant: '#e3e3e0'
typography:
  display-lg:
    fontFamily: Manrope
    fontSize: 34px
    fontWeight: '700'
    lineHeight: 41px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 30px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Manrope
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 25px
  body-lg:
    fontFamily: Manrope
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Manrope
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  margin-main: 20px
  gutter-card: 12px
  stack-gap: 16px
  glass-padding: 8px
---

## Brand & Style

The design system is anchored in the concept of "Dignified Support." It targets a demographic that values care, stability, and premium aesthetics—specifically multi-generational families and professional caregivers. The emotional response is one of safety, warmth, and effortless clarity.

The visual style utilizes a dual-layer philosophy: 
1. **The Navigation Layer (Liquid Glass):** A high-tech, premium interface surface for global controls. It feels like polished, translucent heavy glass that subtly distorts the content beneath it through lensing effects.
2. **The Content Layer (Serene Flat):** A grounded, high-legibility canvas for information. This layer avoids complex shadows to keep focus on care data and communication.

This hybrid approach combines the futuristic precision of iOS 26's "Liquid Glass" with the organic, human warmth of a boutique editorial layout.

## Colors

This design system utilizes a palette inspired by natural, high-end materials.

- **Primary (Soft Sage Green):** Used for growth-oriented actions and success states. It represents vitality and calm.
- **Deep Navy Text:** Provides maximum legibility and a sense of institutional trust. It is used for all primary body text and headings.
- **Warm Amber Accent:** Reserved for moments of attention, notifications, or highlighting important care milestones.
- **Warm Cream Background:** Replaces harsh digital whites with a soft, paper-like surface that reduces eye strain and feels more hospitable.

For the **Liquid Glass** components, use a high-index refraction blur (60px+) with a subtle sage or amber tint depending on the context of the action.

## Typography

The system leverages **Manrope** to capture the clean, modern spirit of SF Pro while offering a slightly more organic and premium character.

- **Headings:** Use tighter tracking and bold weights to establish a clear hierarchy against the cream background.
- **Body:** Set with generous line height to ensure accessibility for older users and caregivers under stress.
- **Lensing Effect:** When text appears behind "Liquid Glass" navigation bars, it should slightly increase in weight or scale to simulate the physical properties of a lens.
- **SF Symbols:** Use the "Rounded" variant of SF Symbols across all UI levels to maintain the soft, approachable aesthetic.

## Layout & Spacing

Designed for the **iPhone 16 Pro**, the layout emphasizes ease of reach and content clarity.

- **Margins:** A consistent 20px horizontal margin ensures content does not feel cramped on the large Pro display.
- **Collapsible Navigation:** Following iOS 26 patterns, the Tab Bar sits as a floating "Liquid Glass" capsule that minimizes into a small pill-shaped indicator during active scrolling, maximizing content real estate.
- **Safe Areas:** Navigation elements are offset from the bottom home indicator by 12px to maintain the floating "Glass" illusion.
- **Rhythm:** An 8px linear scale is used for all internal component spacing.

## Elevation & Depth

Hierarchy is established through **material physics** rather than standard drop shadows.

- **Layer 0 (Background):** The Warm Cream base layer.
- **Layer 1 (Content):** Cards and lists. These are flat with a 1px stroke (#1B2A3A at 5% opacity) to define edges. They do not use shadows.
- **Layer 2 (Liquid Glass):** Navigation bars and primary buttons. These feature a 2px inner "specular highlight" on the top-left edge to simulate light hitting glass. A backdrop-filter with `blur(40px)` and `saturate(150%)` creates the lensing effect.
- **Interaction:** When a user taps a glass element, the lensing effect should intensify (increased scale of background content) to provide tactile feedback.

## Shapes

The design system adopts a **Pill-shaped (Capsule)** language to reflect the "Liquid" theme.

- **Primary Buttons:** Always full-capsule (radius 100px).
- **Cards:** Large radius (24px) to feel soft and friendly.
- **Navigation Bars:** Floating capsules with 32px corner radii.
- **Selection Indicators:** Use "Squircle" shapes (continuous curvature) for a more premium, integrated feel with the iOS hardware.

## Components

### Buttons
- **Primary:** Capsule-shaped with a Sage Green Liquid Glass tint. Features a white specular highlight on the top edge.
- **Secondary:** Transparent with a 1px Sage Green border.

### Tab Bar (iOS 26 Style)
- A floating capsule positioned 12px from the bottom. 
- Active icons use the Sage Green tint; inactive icons use Deep Navy at 40% opacity.
- On scroll, the capsule shrinks to a 44x44pt "Home" pill.

### Cards
- Flat surfaces with #F8F5F0 fill.
- No shadows. Edges are defined by a subtle 1px stroke in Deep Navy (8% opacity).
- Headers within cards use the Amber accent for status dots (e.g., "Active," "Urgent").

### Input Fields
- Soft Cream backgrounds, 2px darker than the page background.
- Floating labels in Deep Navy.
- On focus, the border transforms into a thin Sage Green glow.

### Care Indicators
- Rounded SF Symbols inside 32px circular "Glass" containers. Use the Amber accent for health-critical alerts and Sage Green for routine check-ins.