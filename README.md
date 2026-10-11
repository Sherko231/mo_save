# Mo Save

Single-user, offline-first Flutter app for personal finance tracking and gamified saving goals.

## Active design — simple Home, History and More

The client-requested redesign remains **in progress** until the owner verifies it on-device. The October 2026 simplification replaces the first screen with everyday balances and actions, a dedicated History tab, and a grouped More hub. All prior Savings/Spending accounting screens, goals, settings and historical correction routes remain accessible. Its fund-aware ledger, receipt allocations, Spending dashboard, categorized expenses, future-effective recurring plan versions, internal fund transfers and categorized monthly spending analytics and a true Savings dashboard are committed, but **runtime checks have not been executed**. Verified Savings-backed goals, conditional completion forecasts, evidence-based motivation and the simplified Home/History/More navigation is implemented in source; final client acceptance is still pending. The chronological financial history now offers fund, unit, type, linked-goal and note/category filters, cancelled-event revisions and a separate expected-commitments section. The plan covers linked Savings and Spending funds, real liquidity and categorized expenses, goal earmarks backed by real Savings, overdue-payday dismissal, editable assumptions and realistic goal forecasts.

- [AI implementation contract](AGENTS.md)
- [Redesign product specification](docs/FUNDS_REDESIGN.md)
- [Progress / next Issue / dependency tracker](docs/FUNDS_REDESIGN_PROGRESS.md)
- [GitHub redesign Issues MS-01..MS-18](https://github.com/Sherko231/mo_save/issues/75) (#75–#92)

Read these before continuing project implementation. The tracker begins with MS-01, and previous APK/client acceptance must not be considered redesigned-product sign-off.

## Project docs

- [Product scope](docs/PRODUCT.md)
- [Client-ready roadmap](docs/ROADMAP.md)
- [Simple UX feature-preserving navigation and local walkthrough](docs/SIMPLE_UX_2026_10.md)
- [Earlier UX redesign and interaction architecture](docs/UX_REDESIGN.md)
- [Visual design system](docs/UI_DESIGN_SYSTEM.md)
- [Local data storage](docs/DATA_STORAGE.md)
- [Balance and valuation rules](docs/VALUATION.md)
- [Challenge/ledger reconciliation](docs/CHALLENGE_LEDGER.md)
- [Currency conversion rules](docs/CURRENCY_CONVERSIONS.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Arabic localization and financial formatting](docs/LOCALIZATION_FORMATTING.md)
- [Automated testing and QA](docs/TESTING.md)
- [Android direct APK build](docs/ANDROID_RELEASE.md)

## Current foundation

The app provides Home / History / More adaptive navigation, a ledger-backed financial model, locally persisted saving goals, multi-currency balances and explicit SYP↔USD conversions. The interaction architecture uses progressive disclosure so advanced financial tools remain available without crowding the default experience.
