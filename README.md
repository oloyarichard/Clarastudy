# Edutech Hom — Flutter Frontend

A Flutter client for the Edutech Hom Django REST backend, built with a
modern stack:

- **State management:** Riverpod (`flutter_riverpod`)
- **Routing:** `go_router`, with auth-aware redirects
- **Networking:** `dio`, with automatic JWT refresh-on-401
- **Auth storage:** `flutter_secure_storage`

No code generation is required — all models are hand-written, so
`flutter pub get` is the only setup step before you can run the app.

## 0. Scaffold the native platform folders

This package ships the Dart source (`lib/`) and `pubspec.yaml` only — no
`android/`, `ios/`, or `web/` folders, since those are generated
binaries/boilerplate. From inside this project folder, run:

```bash
flutter create --platforms=android,ios .
```

(add `,web` if you also want to run it in Chrome). Flutter detects the
existing `pubspec.yaml`/`lib/` and only adds the missing platform
folders — it won't touch your dependencies. If you want to double check,
just diff `pubspec.yaml` afterwards; the `dependencies:` block should be
unchanged.

## 1. Point the app at your backend

Open `lib/core/network/api_config.dart` and set the `host` constant:

```dart
static const String host = 'http://10.0.2.2:8000'; // Android emulator default
```

| Where you're running Flutter | Use this host                          |
|-------------------------------|-----------------------------------------|
| Android emulator               | `http://10.0.2.2:8000`                  |
| iOS simulator                  | `http://127.0.0.1:8000`                 |
| Physical device                | `http://<your-computer-LAN-IP>:8000`    |
| Chrome / web                   | `http://127.0.0.1:8000`                 |

Make sure the Django server is actually reachable at that address —
run it with `python manage.py runserver 0.0.0.0:8000` so it accepts
connections from emulators/devices, not just `127.0.0.1`.

## 2. Install dependencies

```bash
flutter pub get
```

## 3. Run

```bash
flutter run
```

## Project structure

```
lib/
  core/            # network client, theme, router, shared widgets, constants
  models/          # hand-written model classes matching the Django serializers
  data/            # repositories — one per backend app (courses, payments, ...)
  providers/       # Riverpod providers wiring repositories into the UI
  features/        # screens, grouped by feature (auth, courses, live_classes, ...)
```

## What's implemented

- **Auth:** register (student/teacher), login, JWT session restore, auto
  token refresh, logout.
- **Courses:** browse/search/filter, detail view with modules & lessons,
  teacher course/module/lesson creation.
- **Enrollments:** enroll in a course, "my courses" on the student
  dashboard.
- **Live classes:** list, schedule (teacher), detail view with a simple
  in-app chat backed by the REST live-chat endpoint.
- **Resources:** browse, upload (teacher/admin), open/download.
- **Assessments:** quiz list, certificate list. Note: the backend does
  **not** expose an endpoint for a quiz's individual questions, so the
  "quiz attempt" screen lets the student record a score (e.g. after
  taking the quiz in class) rather than faking a question flow that
  isn't backed by real data. If you add a `/questions/` endpoint later,
  swap that screen for a real multi-question flow.
- **Payments & wallet:** payment history, wallet balance.
- **Notifications:** list, mark as read, unread badge in the app bar.
- **Chat:** direct message rooms.
- **Profile:** view/edit (including profile picture upload), role badge,
  logout.
- **Role-aware dashboards:** distinct home screens for student, teacher,
  and admin accounts.

## Known simplifications (by design)

- List screens fetch a single page (20 items, matching the backend's
  `PAGE_SIZE`) rather than implementing infinite-scroll pagination —
  straightforward to extend using the `next` cursor already parsed
  into `PaginatedResponse`.
- Live-class and chat "realtime" is REST-based (poll via pull-to-refresh)
  rather than wired to the backend's Django Channels WebSocket
  consumers, since those consumers broadcast messages without
  persisting them to the database. The REST endpoints are the source
  of truth for message history.
- Live class "Join" doesn't embed a WebRTC/video SDK — hook up your
  provider of choice (Agora, Daily, Jitsi, etc.) where indicated in
  `live_class_detail_screen.dart`.
