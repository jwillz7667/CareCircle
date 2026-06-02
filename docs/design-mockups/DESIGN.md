---
name: CareCircle
colors:
  surface: '#f8fbf1'
  surface-dim: '#d8dbd2'
  surface-bright: '#f8fbf1'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f5eb'
  surface-container: '#ecefe6'
  surface-container-high: '#e6e9e0'
  surface-container-highest: '#e0e4db'
  on-surface: '#191d17'
  on-surface-variant: '#434840'
  inverse-surface: '#2e322c'
  inverse-on-surface: '#eff2e9'
  outline: '#73796f'
  outline-variant: '#c3c8bd'
  surface-tint: '#496640'
  primary: '#334f2b'
  on-primary: '#ffffff'
  primary-container: '#4a6741'
  on-primary-container: '#c2e4b4'
  inverse-primary: '#afd0a1'
  secondary: '#605e56'
  on-secondary: '#ffffff'
  secondary-container: '#e6e2d7'
  on-secondary-container: '#66645c'
  tertiary: '#663a4e'
  on-tertiary: '#ffffff'
  tertiary-container: '#815166'
  on-tertiary-container: '#ffcde0'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#caecbc'
  primary-fixed-dim: '#afd0a1'
  on-primary-fixed: '#062104'
  on-primary-fixed-variant: '#324e2a'
  secondary-fixed: '#e6e2d7'
  secondary-fixed-dim: '#cac6bc'
  on-secondary-fixed: '#1c1c15'
  on-secondary-fixed-variant: '#48473f'
  tertiary-fixed: '#ffd8e6'
  tertiary-fixed-dim: '#f2b6ce'
  on-tertiary-fixed: '#330e21'
  on-tertiary-fixed-variant: '#65394d'
  background: '#f8fbf1'
  on-background: '#191d17'
  surface-variant: '#e0e4db'
typography:
  headline-lg:
    fontFamily: Manrope
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  section-header:
    fontFamily: Manrope
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0.01em
  body-primary:
    fontFamily: Manrope
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0em
  body-secondary:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  caption:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  container-max: 1120px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 48px
  card-padding: 24px
---

## Brand & Style
The design system is rooted in the concept of **Empathetic Precision**. It moves away from the sterile, cold aesthetics often associated with medical software, instead embracing a "Quietly Confident" personality. The goal is to reduce cognitive load for families during stressful coordination tasks through a restrained, focused interface.

The visual style draws heavily from **Minimalism** with a **Tactile** touch. It prioritizes vast whitespace to provide "breathing room" for the user, utilizing a warm color palette and soft surface tints to evoke a sense of home and safety rather than a clinic. Every interaction should feel intentional, stable, and warm.

## Colors
The palette is built on a foundation of organic, grounded tones. The **Primary Sage** (#4A6741) acts as the main anchor for actions and progress, symbolizing growth and stability. 

- **Background:** A Warm Cream is used in light mode to reduce eye strain and feel more inviting than pure white.
- **Surface:** Components use pure white or subtle tints of sage to create a clear visual hierarchy through tonal layering.
- **Typography:** Deep Charcoal/Slate is used for all primary text to ensure a minimum contrast ratio of 4.5:1, maintaining crisp legibility against the cream background.
- **Semantic Logic:** Red, Amber, and Green are used sparingly for health statuses. To ensure accessibility, these colors must always be accompanied by a unique icon (e.g., an exclamation mark for warnings).

## Typography
**Manrope** is used across all levels for its modern, geometric construction that retains a friendly, open feel. The typography ramp is intentionally shallow to prevent visual noise.

- **Constraints:** No more than three typography sizes should be present on a single screen to maintain the "restrained" aesthetic.
- **Hierarchy:** Use weight (SemiBold/Bold) rather than size to denote importance for section headers.
- **Reading Comfort:** Body text uses a generous 1.5x line height to ensure clarity for users who may be reviewing medical notes in stressful or low-light environments.

## Layout & Spacing
The layout follows a **Fixed Grid** philosophy on desktop to ensure content remains centered and readable, while transitioning to a fluid model on mobile. 

- **Grid:** A standard 12-column grid is used for desktop, but most content should be confined to the center 8 columns to emphasize whitespace.
- **Rhythm:** An 8px linear scale governs all spacing.
- **Density:** This design system favors "Low Density." Avoid cramming information; if a card feels crowded, increase the `card-padding` or break the content into two separate cards.
- **Reflow:** On mobile, margins reduce to 16px, and all cards stack vertically into a single column.

## Elevation & Depth
Depth is communicated through **Tonal Layers** and extremely soft ambient shadows. This design system avoids high-contrast shadows to maintain its "quiet" nature.

- **Layer 0:** Background (Warm Cream).
- **Layer 1:** Primary Cards (White). These use a very soft, diffused shadow (0px 4px 20px rgba(0,0,0,0.04)) to appear slightly lifted.
- **Layer 2:** Overlays/Modals. These use a slightly more defined shadow and a backdrop blur to focus the user's attention.
- **Inner Depth:** Subtle 1px borders in a slightly darker cream (#E8E4D9) can be used on cards to provide definition without the weight of a shadow.

## Shapes
The shape language is consistently **Rounded**, providing a soft and approachable feel that avoids the "harshness" of sharp corners.

- **Standard Radius:** 0.5rem (8px) for buttons and input fields.
- **Card Radius:** 1rem (16px) for main content containers to create a distinct, friendly silhouette.
- **Iconography:** Use rounded terminals for all custom icons to match the corner radius of the UI components.

## Components
- **Cards:** The primary container. Cards should have a white background and 24px internal padding. Related information (e.g., a list of medications) should be grouped within a single card using subtle horizontal dividers.
- **Buttons:** Primary buttons use the Sage Green background with white text. Secondary buttons use a Sage outline or a subtle cream tint. All buttons must have a minimum height of 48px for touch accessibility.
- **Input Fields:** Use a subtle background tint (Secondary Cream) rather than a heavy border. Focus states are indicated by a 2px Sage Green border.
- **Chips/Badges:** Used for status (e.g., "Upcoming," "Completed"). These should have a low-saturation background and high-contrast text.
- **Lists:** Use generous vertical spacing (16px) between items. Each list item should have a clear trailing icon or chevron if it is interactive.
- **Checkboxes & Radios:** Use the Primary Sage for the "Checked" state. Ensure the hit area is at least 44x44px.