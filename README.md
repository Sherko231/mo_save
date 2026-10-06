# Mo Save

Single-user, offline-first Flutter app for personal finance tracking and gamified saving goals.

## Project docs

- [Product scope](docs/PRODUCT.md)
- [Client-ready roadmap](docs/ROADMAP.md)
- [UX redesign and interaction architecture](docs/UX_REDESIGN.md)
- [Local data storage](docs/DATA_STORAGE.md)
- [Balance and valuation rules](docs/VALUATION.md)
- [Challenge/ledger reconciliation](docs/CHALLENGE_LEDGER.md)
- [Currency conversion rules](docs/CURRENCY_CONVERSIONS.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Arabic localization and financial formatting](docs/LOCALIZATION_FORMATTING.md)
- [Automated testing and QA](docs/TESTING.md)
- [Android production release](docs/ANDROID_RELEASE.md)

## Current foundation

The app provides Home / Saving Goals / Settings navigation, a ledger-backed financial model, locally persisted saving goals, multi-currency balances and explicit SYP↔USD conversions. The interaction architecture uses progressive disclosure so advanced financial tools remain available without crowding the default experience.
