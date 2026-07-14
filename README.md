# PULLMED

Flutter application (Android/iOS) for entering medical data and writing it to an NFC tag, part of the **PULLMED** project — an NFC-based medical-ID wristband for emergency use.

## Overview

- Login and authentication via Supabase
- Entry and editing of medical history (anamnesis)
- Generation of a unique per-user URL and writing it to the wristband's NFC tag
- Companion website that renders the record from the URL

## Prerequisites

- Flutter SDK
- Android Studio (for Android) or Xcode (for iOS) to build on devices

## Running the app

Supabase keys are passed at build time via `--dart-define` and **must not be hard-coded in the source**.

Android:

```bash
flutter pub get
flutter run -d <device> \
  --dart-define=SUPABASE_URL="https://your.supabase.url" \
  --dart-define=SUPABASE_ANON_KEY="your-anon-key"
```

iOS:

- Open `ios/Runner.xcworkspace` in Xcode and set up signing (Team).
- Run on a physical device — NFC does not work in the simulator.

## Security and secrets

- Do not keep sensitive keys in the source code. Use `--dart-define` or environment variables.
- Make sure Supabase Row Level Security (RLS) is enabled.
- Optional: keep a local `.env` file out of version control (already covered by `.gitignore`).

## Continuous integration (CI)

- The workflow in `.github/workflows/flutter.yml` runs `flutter analyze` and `flutter test` on pushes and pull requests.

## How to cite

If you use this project, please cite the versioned archive deposited on Zenodo:

> G. Cianciarullo, B. B. Sardinha, G. I. F. Graziosi, T. G. da Silva, and L. Blassioli, *PULLMED: Source Code and Supplementary Materials for an Open, Low-Cost NFC Medical-ID Wristband*. Zenodo, 2025. DOI: 10.5281/zenodo.21084083

## License

Released under the MIT License. See the [LICENSE](LICENSE) file for the full terms.
