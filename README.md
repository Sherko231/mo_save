# Mo Save

Single-user, offline-first Flutter app for personal finance tracking and gamified saving goals.

## Active redesign — savings and spending funds

The client-requested redesign is **in progress**. Its fund-aware ledger and actual-receipt allocation foundation are committed, but **runtime checks have not been executed**, and Spending/Savings dashboards, goal backing and full acceptance are still future issues. The plan covers linked Savings and Spending funds, real liquidity and categorized expenses, goal earmarks backed by real Savings, overdue-payday dismissal, editable assumptions and realistic goal forecasts.

- [AI implementation contract](AGENTS.md)
- [Redesign product specification](docs/FUNDS_REDESIGN.md)
- [Progress / next Issue / dependency tracker](docs/FUNDS_REDESIGN_PROGRESS.md)
- [GitHub redesign Issues MS-01..MS-18](https://github.com/Sherko231/mo_save/issues/75) (#75–#92)

Read these before continuing project implementation. The tracker begins with MS-01, and previous APK/client acceptance must not be considered redesigned-product sign-off.

## Project docs

- [Product scope](docs/PRODUCT.md)
- [Client-ready roadmap](docs/ROADMAP.md)
- [UX redesign and interaction architecture](docs/UX_REDESIGN.md)
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

The app provides Home / Saving Goals / Settings navigation, a ledger-backed financial model, locally persisted saving goals, multi-currency balances and explicit SYP↔USD conversions. The interaction architecture uses progressive disclosure so advanced financial tools remain available without crowding the default experience.
