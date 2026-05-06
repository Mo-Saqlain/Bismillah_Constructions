# Bismillah Constructions

A simple offline-first app to run a small construction business by yourself.
Track projects, suppliers, banks/wallets, materials and labour — and see
where every rupee went.

---

## What you can do with it

- **Home** — see your cash on hand, payables, profit and recent activity.
- **New Transaction** — record a Material Buy, Labour Payment, Supplier
  Payment, Receive From Project, Wallet Transfer or Service Fee. Each one
  updates the books automatically.
- **Reports** — Income Statement, Balance Sheet, Cash Flow, Aging,
  Project Budget vs Actual, Wage Register, plus per-supplier, per-bank
  and per-project ledgers (export as PDF or CSV).
- **Manage** — add/edit your Projects, Suppliers, Banks/Wallets and
  Material Types in one place.
- **Settings** — switch theme, run/share/import a backup, browse the
  audit log of everything that changed.

Everything is stored locally on the device. Backups can be saved to the
device and shared via WhatsApp / Gmail / Drive.

---

## Build it yourself

You only need three commands once the prerequisites are in place:

```bash
flutter clean
flutter pub get
flutter build apk --release
```

The signed APK lands at:

```
build/app/outputs/flutter-apk/app-release.apk
```

Install that file on any Android phone or tablet.

### What you need installed first

1. **Flutter SDK 3.x** — <https://docs.flutter.dev/get-started/install>
   (includes the Dart SDK).
2. **Android Studio** (or just the **Android command-line tools** + SDK)
   — needed for the Android build toolchain.
   - Install **Android SDK Platform 34** from the SDK Manager.
   - Install **Android SDK Build-Tools** and **Android SDK Command-line Tools**.
3. **Java JDK 17** — bundled with recent Android Studio installs; otherwise
   install it separately and make sure `JAVA_HOME` points at it.
4. **Git** — to clone the project.

After installing, run `flutter doctor` once and fix anything it flags
(usually "Android licenses not accepted" — fix with `flutter doctor
--android-licenses`).

### Want a smaller APK?

```bash
flutter build apk --release --split-per-abi
```

This produces three smaller APKs (one per CPU architecture) instead of
one large universal APK.

### Want to run it on your desktop?

```bash
flutter run            # run on a connected phone or emulator
flutter run -d windows # run as a Windows app
```

### Tip for Windows + OneDrive users

If your project folder is inside OneDrive, the Android build can fail
with a permission error. Move the project somewhere outside OneDrive
(e.g. `C:\projects\bismillah`) before building.

---

## Folder structure (just the bits you'll touch)

```
bismillah_constructions/
├── lib/                ← all the Dart code lives here
│   ├── main.dart       ← app entry point
│   ├── app.dart        ← theme + top-level setup
│   ├── core/           ← constants, formatters, theme colours
│   ├── data/           ← database, models, repositories
│   ├── providers/      ← state plumbing (Riverpod)
│   └── features/       ← one folder per screen area
│       ├── home/         dashboard tab
│       ├── dashboard/    home page widgets
│       ├── transactions/ new-txn form, history
│       ├── projects/     project list & detail
│       ├── parties/      suppliers + banks/wallets
│       ├── reports/      every report & ledger screen
│       ├── manage/       the "Manage" tab
│       └── settings/     theme, backup, audit, material types
├── android/            ← Android build config (rarely touched)
├── assets/             ← logo + images
└── pubspec.yaml        ← dependencies list
```

If you want to change a screen, find it under `lib/features/<area>/` and
edit it directly. If you want to change colours or fonts, look in
`lib/core/theme.dart`.

---

## When something goes wrong

- **`flutter pub get` fails** → check your internet, then re-run.
- **APK build fails on Android licenses** → run
  `flutter doctor --android-licenses` and accept all.
- **App opens but data looks empty** → on first run that's normal; tap
  "+ New Transaction" to start.
- **Lost data after reinstall** → backups are in
  `Documents/Bismillah_Backups/` on Android — use Settings → "Import
  backup" to restore.

That's it. Three commands and you're shipping.
