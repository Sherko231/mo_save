# Mo Save — Initial setup and editable defaults

## Fresh install

A truly fresh database starts in a one-time setup screen before the normal Home / Challenges / Settings shell is shown.

The setup screen is prefilled with the approved client plan, but every supported assumption is editable from the app:

- weekly SYP income and weekday;
- monthly USD income and payday;
- recurring monthly expense items;
- reference SYP/USD valuation rate;
- reference gold USD-per-gram price;
- weekly expenses and savings envelope defaults;
- weekly, monthly and goal notification preferences.

The recurring expense plan can be opened directly from setup/Settings. Every item can be added, edited or deleted, including deleting all items and rebuilding the plan from an empty list.

The one-time setup is considered complete only after the user saves the financial values and notification preferences. Completion is stored in `app_metadata` under `initial_setup_complete_v1`.

## Existing installations

Issue #23 introduces the setup gate after earlier versions already stored user data. Existing installations must not be forced through onboarding after an update.

If the setup-complete metadata key is absent but the database already contains financial settings, financial events, challenges or recurring-expense rows, `AppSetupStorage` treats it as an existing installation and writes the completion marker automatically.

A brand-new database is checked before notification startup can seed the financial-settings row, so it still enters the first-run setup flow correctly.

## Future defaults versus history

Settings are future-facing configuration. Changing an income amount, payday, valuation reference, envelope proposal or notification preference does not rewrite already-recorded financial events.

Historical movements remain owned by the transaction ledger. Corrections to recorded history must use the transaction-history correction flow instead of changing Settings.

Recurring expense-plan items are also planning defaults. Editing or deleting a plan item changes future/current planning displays; it does not delete previously recorded expense events.

## Ongoing configuration

After setup is completed, the same controls remain available in the normal Settings tab. No code change or app update is required to change supported client assumptions.
