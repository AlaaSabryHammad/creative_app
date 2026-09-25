# CREATIVE — Flutter app

Native iOS/Android companion of the web app at `../OverTime-Project` (live: https://overtime.alhemedy.com).
Same Supabase backend, permissions and rules — the full API is documented in `../OverTime-Project/docs/API.md`.

## Run
```bash
flutter pub get
flutter run            # pick an iPhone simulator or Android emulator
flutter test           # business-rule tests (day type, amounts, BOQ, alerts, notes)
```

## Structure
- `lib/core/theme.dart` — design tokens copied from the web (colors, Tajawal font, radii)
- `lib/core/logic.dart` — shared rules: overtime amount (hours × rate), day type, alerts, BOQ totals, missing-data notes
- `lib/data/store.dart` — Supabase auth, `profiles`, `app_state` collections, versioned `save_state`, realtime, signed file URLs
- `lib/data/ai.dart` — Claude assistant (Messages API over HTTPS; there is no official Dart SDK)
- `lib/ui/` — login, navigation drawer (same sections/permissions as the web sidebar) and screens

## Scope (v1)
View everything the web shows; do the daily actions on mobile: record overtime hours, approve/reject requests,
chat with the AI assistant, change password. Creating/editing projects, workers, documents, vehicles, settings and
users is done on the website.
