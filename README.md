# AuraExpense — Personal Finance Tracker

Offline-first expense tracker with a Flutter mobile client and a FastAPI server that enriches transactions via Ollama (Qwen3-8B) over a Tailscale mesh network.

## Project structure

```
personal_finance/
├── client/          # Flutter app (iOS, Android, macOS)
├── server/          # FastAPI gateway + SQLite
└── architecture_spec.md
```

## Prerequisites

- **Flutter** 3.x ([install guide](https://docs.flutter.dev/get-started/install))
- **Python** 3.9+
- **Ollama** with `qwen3:8b` pulled (for AI enrichment on the server)
- **Tailscale** (optional, for remote sync between phone and home lab)

## Quick start

```bash
# Install all dependencies
make setup

# Terminal 1 — start the API server
make server

# Terminal 2 — run the Flutter app
make client
```

## Server configuration

Copy the example env file and adjust as needed:

```bash
cp server/.env.example server/.env
```

| Variable       | Default                    | Description              |
|----------------|----------------------------|--------------------------|
| `OLLAMA_URL`   | `http://127.0.0.1:11434`   | Ollama API endpoint      |
| `OLLAMA_MODEL` | `qwen3:8b`                 | Model for enrichment     |

Pull the model if you haven't already:

```bash
ollama pull qwen3:8b
```

## Client configuration

The Flutter client connects to your Tailscale node by default using the device shortname (`akhilesh`). Override the host at build/run time:

```bash
cd client
flutter run --dart-define=SERVER_HOST=akhilesh
```

For local development against a server on the same machine:

```bash
flutter run --dart-define=SERVER_HOST=127.0.0.1
```

### Deploy to iPhone (release)

List connected devices, then install a release build on your phone:

```bash
make ios-devices
make ios-release DEVICE="Akhilesh's iPhone (wireless)"
```

Use the exact name from `make ios-devices`. Override the backend host if needed:

```bash
make ios-release DEVICE="Akhilesh's iPhone (wireless)" SERVER_HOST=akhilesh
```

### Share Android APK

**Option A — GitHub Actions (no Android Studio required)**

Push a version tag to trigger an automatic APK build. The workflow uploads the APK as a
GitHub Actions artifact and attaches it to the GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Download the APK from the **Releases** page or the workflow run's **Artifacts** tab.
You can also run the workflow manually from the **Actions** tab.

To change the backend host for CI builds, edit `SERVER_HOST` in
`.github/workflows/android-release-apk.yml` (or set a repository variable named
`SERVER_HOST` and update the workflow to use it).

**Option B — Build locally**

```bash
make android-apk
```

The file is written to `dist/TapEx-release.apk` (also under `client/build/app/outputs/flutter-apk/app-release.apk`).

Recipients must allow install from unknown sources. The app expects your Tailscale backend at `akhilesh` by default.

## Testing

```bash
# Client unit tests (regex parser)
make test-client

# Server integration test (requires running server + Ollama)
make test-server

# Server health check
make health
```

## API endpoints

| Method | Path                    | Description                          |
|--------|-------------------------|--------------------------------------|
| GET    | `/health`               | Server health + Ollama config        |
| POST   | `/api/v1/sync`          | Push pending transactions (202)      |
| GET    | `/api/v1/sync/status`   | Pull enriched transaction states     |
