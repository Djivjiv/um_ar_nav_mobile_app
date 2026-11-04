# UM-AR Nav

Flutter navigation app for the University of Mindanao Matina Campus.
Connects to an existing Supabase backend. Targets Android and iOS.

## Setup

```bash
flutter pub get
```

### Keys

No keys are kept in the source. Three values are passed at run/build time
with `--dart-define`:

| Define | Value |
| --- | --- |
| `SUPABASE_URL` | Project URL, e.g. `https://YOUR-PROJECT.supabase.co` |
| `SUPABASE_ANON_KEY` | Project anon key. It is public by design; its safety depends entirely on the database's RLS policies |
| `MAPTILER_KEY` | MapTiler API key |

If one is missing, the app opens on a "Setup required" screen that names it.

Run on a device, debug:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
```

Run on a device, release:

```bash
flutter run --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
```

Build an Android APK, debug:

```bash
flutter build apk --debug --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
```

Build an Android APK, release:

```bash
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
```

Build an Android App Bundle, release:

```bash
flutter build appbundle --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
```

Build for iOS, release (on a Mac; add
`--dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID` for Google sign-in):

```bash
flutter build ipa --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
```

To avoid typing them, put the values in `dart_defines.json`, which git
ignores, and replace the three defines with
`--dart-define-from-file=dart_defines.json`:

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_ANON_KEY",
  "MAPTILER_KEY": "YOUR_MAPTILER_KEY"
}
```

### Assets

`assets/images/umlogo.png` is the University of Mindanao seal. Every logo
usage has an icon fallback if the asset fails to load.

## Architecture

- **State**: `flutter_bloc` cubits (`auth`, `building`, `search`,
  `outdoor_nav`, `indoor_nav`)
- **Routing**: `go_router` with an auth/visitor redirect guard
  (`lib/presentation/routes/app_router.dart`)
- **Data**: repositories over `supabase_flutter`
  (`lib/data/repositories/`), models in `lib/data/models/`
- **Pathfinding**: `DijkstraService.search` is the app's one Dijkstra, used
  by the outdoor, indoor, multi-phase and AR routes; `InstructionService`
  turns bearings into turn-by-turn text. Both in `lib/domain/services/`
- **Map**: `flutter_map` v8 with cached MapTiler tiles
  (`lib/presentation/widgets/um_map_widget.dart`)

Session rules:

- Sign-in is by school Google account only. An email in the student format
  (`first initial.lastname.idnumber@umindanao.edu.ph`) becomes a verified
  student automatically. Any other school email picks a role and waits for
  an admin. The formats are in `lib/core/config/email_role_config.dart`.
- Pending, rejected and inactive accounts can't use the app and see a short
  explanation. This is checked at sign-in, on launch and on each return to
  the app.
- Signed-in users stay signed in across app restarts for 8 hours from
  sign-in (`user_profiles.session_start`, with a local fallback). After that
  the splash screen signs them out and shows the login screen.
- Visitor sessions last 2 hours and are restored on restart until they
  expire. The server starts and times them (`supabase/visitor_sessions.sql`
  must be run first, or "Continue as Visitor" fails while online). The app
  keeps the server's time and counts on from it, offline too, so changing the
  phone's clock can't extend a session. At expiry the visitor is signed out
  and can start a new session or log in.
- Visitors can't see the 2D indoor map: the indoor part of a route shows
  numbered written steps instead. The outdoor map and AR are the same for
  everyone. `canSeeIndoorMap` in `auth_state.dart` is the rule.
- Visitor trips and SUS answers carry the install's `device_code`, and the
  database flags them with `is_visitor` (no `user_id`).

Feedback rules:

- The SUS is asked once per person: `user_id` when signed in, else
  `device_code`. The phone keeps a flag, so this works offline, and asks the
  server too (`supabase/sus_once_per_person.sql`), which also holds the unique
  rule.
- After the SUS, and on each later arrival, an optional comment card appears
  once per trip. Signed-in users also have one on the profile screen.
  Comments go to `feedback_comments` (`supabase/feedback_comments.sql`).
- SUS answers and comments wait in the write queue until they reach the
  server, so neither is lost to a bad connection.

## Enabling screenshot blocking

Built but switched off. To turn it on, change one line in
`lib/core/config/app_config.dart`:

```dart
const bool kBlockScreenCapture = true;
```

Set it back to `false` while gathering data and finishing the paper.

Android only. It covers the whole app. When on, it blocks:

- screenshots
- screen recording
- screen mirroring
- the recent-apps preview

It cannot stop:

- a photo of the screen taken with another device
- capture on a rooted phone

## Before a phone test

1. **Run the SQL first**, in the Supabase SQL editor, in this order. None of
   it runs by itself.
   1. Admin app `db/user_roles.sql` (`public.is_admin()`)
   2. `supabase/navigation_evaluation.sql`
   3. `supabase/visitor_sessions.sql`
   4. `supabase/sus_once_per_person.sql`, one section at a time
   5. `supabase/feedback_comments.sql`

2. **Check the flags** in `lib/core/config/app_config.dart`:

   | Flag | Now | For a phone test |
   | --- | --- | --- |
   | `kDevCoordinateTools` | Follows the build: on in debug, off in release | Use `--release` to see what users see |
   | `kBlockScreenCapture` | `false` | Leave `false` while gathering data, so screenshots still work |
   | `_forceSkipGeofence` | `true`: the campus check is off in every build | Leave `true` off campus. Set `false` to test the campus check, on campus |

3. **Run the app** with a phone connected:

   ```bash
   flutter run --release --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY --dart-define=MAPTILER_KEY=YOUR_MAPTILER_KEY
   ```

4. **Try these:**
   - **Sign-in:** sign in with a school Google account, close the app, and
     check you stay signed in. A non-student email picks a role and waits for
     an admin.
   - **Visitor:** tap "Continue as Visitor", close and reopen the app, and
     check the session continues. The 2D indoor map stays hidden.
   - **SUS:** finish a trip and answer the SUS. The next arrival offers the
     optional comment instead, and the SUS is not asked again.
   - **AR card:** start an AR trip to a room or facility from the Map tab and
     from the AR tab. Each shows that place's card, not the building's.
   - **Offline:** with the app used online once, turn on airplane mode and
     restart it. The map, search and routes still work, the map stops
     zooming out at 16, and a SUS sent now reaches the server once back online.

## Verify

```bash
flutter analyze
flutter test
```
