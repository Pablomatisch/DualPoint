# Design

DualPoint should feel like a small, precise macOS utility: quiet surfaces, one
accent, restrained motion and copy that stays out of the way.

## Principles

1. **One cursor, one accent.** The interface never competes with the pointer.
   A single violet accent marks the active thing; everything else is glass.
2. **Show state once.** A status appears in one place per screen. The active
   device is marked by the accent edge of its row, not by a second badge.
3. **Earn every sentence.** Labels are short, sentence case and action-oriented.
   Explanations live in the place where the decision is made, not repeated in
   the header, the card and the footer.
4. **Depth without noise.** Translucency, soft edges and a short shadow convey
   layering. There are no hard borders or bright dividers.
5. **Motion explains, never delays.** Springs are short and damped; content
   transitions are subtle.

## Palette

Tokens live in `Sources/DualPoint/Views/Brand.swift`.

| Token | Use |
| --- | --- |
| `accent` `#7570FF` (approx.) | Primary actions, active state, focus |
| `violet` | Gradient partner for the accent |
| `cyan` | Built-in display highlights |
| `success` | Granting permissions, enabled states |
| `warning` | Paused switching, missing permissions |
| `danger` | Destructive actions and errors |
| `textPrimary` 95% white | Titles and primary labels |
| `textSecondary` 62% white | Supporting copy |
| `textTertiary` 36% white | Metadata, section labels |
| `surface` 6% white | Quiet fills |
| `cardGradient` | Cards, from 7.5% to 3.2% white |
| `panelTint` | Dark translucent menu bar panel |

All surfaces use continuous corner radii. Cards sit between 14–18 pt; the panel
uses 22 pt.

## Typography

- Rounded system font for names, titles and the brand.
- Standard system font for body copy and controls.
- Monospaced font only for log lines.
- Sizes: 27 pt screen title, 14–17 pt card titles, 11–12 pt body,
  9.5–10.5 pt metadata, 8–9.5 pt all-caps section labels with 1.4 pt tracking.

## Layout

| Surface | Metrics |
| --- | --- |
| Menu bar panel content | 400 × 404 pt |
| Panel window | 448 × 436 pt, 22 pt corners |
| Panel insets | 20 pt sides, 16 pt top / 13 pt header bottom |
| Settings window | 860 × 600 pt minimum |
| Settings sidebar | 228 pt |
| Settings content | 30 pt sides, 46 pt top, 760 pt max width |
| Setup window | 740 × 700 pt minimum |
| Setup content | 32 pt sides, 24 pt top |

The panel window keeps an 8 pt top inset and 24 pt side/bottom inset so its
shadow has room while the panel never covers the menu bar item that opened it.
Section labels and trailing counts share the same 20 pt content inset as the
cards, so nothing sits against an edge.

## Surfaces

- `PanelBackground` — `NSVisualEffectView` (`.hudWindow`, behind-window) with a
  dark tint, accent wash and a 1 pt light edge.
- `GlassCard` — layered white gradient, 18 pt radius, soft shadow.
- `HoverCard` — same glass, with a brighter gradient and edge on hover and a
  stronger accent border for the active device row.
- `VisualEffectView` — native vibrancy for the Settings sidebar.

## Motion

| Interaction | Motion |
| --- | --- |
| Panel open | spring `response 0.34`, `damping 0.86`, fade 0.18 s |
| Panel close | ease-in 0.12 s, fade 0.14 s |
| Settings tab change | ease-out 0.22 s, 10 pt rise |
| Onboarding step | spring `response 0.40`, `damping 0.88`, 22–26 pt horizontal slide |
| Hover | ease-out 0.15 s |
| Filter chips | ease-out 0.14 s |

## Screens

### Menu bar panel

Header with brand and Settings. Then the device list with a per-device display
menu, and a footer with the automatic-switching toggle plus Settings / Setup /
Quit. There is no separate active-device hero box: the active row is marked by
the accent edge, and the header no longer repeats a live status.

### Settings

Four tabs: General, Devices, Activity, About. The sidebar holds the brand,
status, navigation and — only while setup is incomplete — a “Finish setup” card.
General covers switching, permissions and login. Devices shows assignment rows
and a live display map. Activity shows the last switch and a filterable local
log. About is a short statement of purpose plus version information.

### Setup

Four steps: welcome, permission, assignments, test drive. The top bar shows only
“DualPoint Setup” and “Step *n* of 4”; the page itself carries the heading. The
test-drive step temporarily enables switching so the handover can be felt before
setup is committed.

## Copy voice

- Prefer verbs: “Switch automatically”, “Grant Input Monitoring”, “Move with
  USB Optical Mouse”.
- Keep subtitles to one line where possible.
- Do not repeat the screen title in the header, the card and the footer.
- Say “restores its last position” rather than explaining anchors.
- Never claim a hardware behavior in the UI that has not been tested; the
  testing status lives in `docs/TESTING.md`.
