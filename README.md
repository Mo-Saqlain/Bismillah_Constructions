# Bismillah Constructions ERP

Offline-first, double-entry construction-project ledger built in Flutter.
Designed for a single operator running multiple sites: cash, banks,
suppliers, materials, labour, and project P&L — all in one place,
backed up locally.

## Documentation

The documentation is split into two focused files:

- **[USER_MANUAL.md](USER_MANUAL.md)** — for the operator. How to use
  the app: tabs, transactions, project lifecycle, the dashboard,
  reports, backup & restore, FAQs.
- **[TECHNICAL.md](TECHNICAL.md)** — for engineers. Architecture, data
  model, schema, repositories, providers, transaction kinds, reporting
  engine, backup mechanics, error reporting, build & test instructions.

## Quick start

```bash
flutter pub get
flutter run                  # connected phone / emulator
flutter run -d windows       # Windows desktop
flutter test                 # 75 automated tests
```

For release builds and deployment, see
[TECHNICAL.md §13 Build & run](TECHNICAL.md#13-build--run).

## License

Internal — © Bismillah Constructions.
