# UM-AR Nav

Flutter navigation app for the University of Mindanao Matina Campus.
Connects to an existing Supabase backend. Targets Android and iOS.

## Setup

```bash
flutter pub get
```

### Supabase anon key

The anon key is **not** committed. Provide it at run/build time:

```bash
flutter run   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
flutter build apk  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
flutter build ios  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Alternatively replace `_fallbackAnonKey` in
`lib/core/config/supabase_config.dart`.

The Supabase URL and MapTiler keys are already configured in
`lib/core/config/`.

### Assets

`assets/images/umlogo.png` is a placeholder — drop in the real UM logo
(PNG) at that path. Every logo usage has an icon fallback if the asset
fails to load.

## Architecture

- **State**: `flutter_bloc` cubits (`auth`, `building`, `search`,
  `outdoor_nav`, `indoor_nav`)
- **Routing**: `go_router` with an auth/visitor redirect guard
  (`lib/presentation/routes/app_router.dart`)
- **Data**: repositories over `supabase_flutter`
  (`lib/data/repositories/`), models in `lib/data/models/`
- **Pathfinding**: `DijkstraService` (outdoor + indoor) and
  `InstructionService` (bearing → turn-by-turn text) in
  `lib/domain/services/`
- **Map**: `flutter_map` v8 with cached MapTiler tiles
  (`lib/presentation/widgets/um_map_widget.dart`)

Session rule: the app always starts at login — any persisted Supabase
session is cleared on cold start. Visitor sessions last 2 hours
(`visitor_sessions` table).

## Verify

```bash
flutter analyze      # 0 issues
flutter test         # SUS scoring + theme smoke test
flutter build apk --debug --dart-define=SUPABASE_ANON_KEY=...
```
