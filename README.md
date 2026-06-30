# AuraExpense — Personal Finance Tracker

Offline-first expense tracker with a Flutter mobile client and a FastAPI server. Transactions are enriched on-device via OpenRouter (key shared from the server) with an Ollama fallback on the server, synced over a Tailscale mesh network.

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

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Ollama API endpoint (server fallback + import parsing) |
| `OLLAMA_MODEL` | `qwen3:8b` | Ollama model |
| `OPENROUTER_API_KEY` | — | Shared with tailnet clients for on-device enrichment |
| `OPENROUTER_MODEL` | `openrouter/free` | Free OpenRouter model only (`openrouter/free` or `*:free`) |
| `ENRICHMENT_SOFT_TIMEOUT` | `60` | Soft timeout (seconds) |
| `ENRICHMENT_HARD_TIMEOUT` | `300` | Hard timeout (seconds) |

**Ollama** (local): pull `qwen3:8b` on the server host. Used when the client has not pre-enriched a transaction, and for bulk import parsing.

**OpenRouter** (cloud, free models): set `OPENROUTER_API_KEY` on the server. All devices on your tailnet fetch it via `GET /api/v1/enrichment/config` during sync and enrich transactions on-device before pushing to the server.

## Client configuration

Configure the sync server **inside the app** (gear icon on the dashboard):

1. Enter your server’s Tailscale **hostname** manually (e.g. `akhilesh`), or
2. Paste a [Tailscale API key](https://login.tailscale.com/admin/settings/keys) and tap **Refresh tailnet devices** to pick from your tailnet.

The API key is stored securely on-device and is only used to list tailnet machines.

For local development against a server on the same machine, set hostname to `127.0.0.1`.

**Optional build-time seed:** pass `--dart-define=SERVER_HOST=hostname` to pre-fill the host on first launch only (useful for CI or dev builds):

```bash
cd client
flutter run --dart-define=SERVER_HOST=akhilesh
```

### Deploy to iPhone (release)

List connected devices, then install a release build on your phone:

```bash
make ios-devices
make ios-release DEVICE="Akhilesh's iPhone (wireless)"
```

Use the exact name from `make ios-devices`. Optionally seed the default host on first launch:

```bash
make ios-release DEVICE="Akhilesh's iPhone (wireless)" SERVER_HOST=akhilesh
```

### Share Android APK

**Option A — GitHub Actions (no Android Studio required)**

Push a version tag to trigger an automatic APK build. The workflow derives the Android
`versionName` and a monotonic `versionCode` from the tag, so newer tags install cleanly
over older ones. It uploads the APK as a GitHub Actions artifact and attaches it to the
GitHub Release:

```bash
git tag v1.2.0
git push origin v1.2.0
```

Download the APK from the **Releases** page or the workflow run's **Artifacts** tab.
You can also run the workflow manually from the **Actions** tab.

> **Versioning note:** `pubspec.yaml` ships a fixed `version: 1.0.0+1`, which is only a
> fallback for local/dev builds. Android decides upgrade-vs-conflict by the integer
> `versionCode`, so release builds **must** override it. Always cut releases via a `vX.Y.Z`
> tag (or pass `VERSION=` locally) — otherwise every APK embeds the same `versionCode` and
> the phone reports a package conflict.

**Option B — Build locally**

```bash
# Pass VERSION so the APK gets a proper versionName/versionCode
make android-apk VERSION=1.2.0
```

The file is written to `dist/TapEx-release.apk` (also under `client/build/app/outputs/flutter-apk/app-release.apk`).

Recipients must allow install from unknown sources. Configure the sync server in the app after install (Settings → tailnet devices or manual hostname).

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
| GET    | `/health`               | Server health + enrichment provider config |
| GET    | `/api/v1/enrichment/config` | OpenRouter credentials for tailnet clients |
| POST   | `/api/v1/sync`          | Push pending transactions (202)      |
| GET    | `/api/v1/sync/status`   | Pull enriched transaction states     |
| POST   | `/api/v1/import`        | Import `.txt`/`.csv` file content (202) |
| POST   | `/api/v1/sync/deletes`  | Push pending delete IDs              |
| PUT    | `/api/v1/transactions/{id}` | Update a transaction             |
| DELETE | `/api/v1/transactions/{id}` | Delete a transaction             |

### Import from file

1. Ensure the server is reachable (Tailscale or local).
2. In the app, tap the upload icon next to the expense entry field.
3. Choose a `.txt` or `.csv` file. Each line (or CSV row) should describe one expense.
4. The server parses the file with Ollama, creates transactions, and returns them with `sync_status: processing`.
5. The app stores them locally and polls until enrichment completes.

**Request** — `POST /api/v1/import`

```json
{
  "content": "1450 zoom subscription @work\n45.90 dinner @night",
  "format": "text"
}
```

Use `"format": "csv"` for comma-separated files.

**Response (202)**

```json
{
  "status": "accepted",
  "message": "Importing 2 transactions",
  "transactions": [
    {
      "id": "uuid",
      "raw_input": "1450 zoom subscription @work",
      "amount": 1450.0,
      "description": "zoom subscription",
      "tag": "work",
      "display_label": "Zoom Subscription",
      "merchant": null,
      "ai_confidence": null,
      "is_recurring": false,
      "sync_status": "processing",
      "created_at": "2026-06-21T12:00:00",
      "updated_at": "2026-06-21T12:00:00"
    }
  ]
}
```

### Display labels

After sync enrichment, each transaction includes a `display_label` — a short, human-readable title generated by the LLM. The mobile UI shows `display_label` when available, falling back to the regex-parsed `description`. The original user text is always preserved in `raw_input` and mapped by transaction `id`.
