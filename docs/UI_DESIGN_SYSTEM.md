# Mo Save — Visual Design System

## Direction

Mo Save uses a calm fintech visual language: deep emerald for trust and progress, warm neutral surfaces for long-session comfort, and restrained gold accents for value and milestones. The interface should feel premium without becoming decorative or visually noisy.

The UI keeps the progressive-disclosure UX architecture already established. This pass changes presentation, not financial behavior.

## Core visual rules

- One dominant visual anchor per screen. On Home and goal detail this is the financial/goal hero card.
- Strong hierarchy through scale, contrast and spacing instead of many borders or competing colors.
- Warm, low-contrast surfaces for secondary content; saturated color is reserved for primary actions, states and data emphasis.
- Emerald represents healthy/primary financial state, gold represents value/milestones, red is reserved for destructive/overdue/expense emphasis, violet is used for currency conversion, and blue is used for USD-related context.
- Rounded geometry is consistent: 18dp controls, 22–24dp cards, 28–30dp hero surfaces and sheets.
- Primary touch targets stay at or above 48dp.
- Dark mode follows the system automatically and preserves the same hierarchy.
- No glassmorphism, heavy gradients, neon colors or decorative effects that reduce readability.

## Main surfaces

### Home

The hero card owns the strongest visual weight and presents total estimated value plus major asset chips. Monthly income/expense summaries use compact tinted metric cards. Attention items use semantic status tones. Advanced operations remain inside progressive-disclosure cards.

### Saving goals

Goal cards use a state-aware accent and a strong progress treatment. Completed, overdue and active goals remain visually distinguishable without relying on text alone. Goal detail uses a premium hero and tactile grid cells; completed cells become saturated emerald tiles with a clear check state.

### Settings

Configuration remains grouped by task. Each group uses a consistent icon badge and expandable surface. Initial setup gets a branded hero so it feels intentional rather than like a long form.

### Transaction history

Each event type receives a stable visual tone and icon. Amount/summary is visually stronger than metadata. Deleted/revised states appear as compact semantic pills.

## Accessibility

The palette is designed around high foreground/background contrast, Material controls preserve large hit areas, status never relies on color alone, and saving-grid cells keep explicit checked semantics for accessibility services.

## Data safety

This visual redesign does not change SQLite schema, ledger calculations, recurrence logic, identifiers, backup format, or stored financial values.
