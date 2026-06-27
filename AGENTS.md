# AGENTS.md

## Cursor Cloud specific instructions

This repo is **AuraExpense / TapEx**: an offline-first expense tracker with a Flutter client (`client/`) and a FastAPI + SQLite server (`server/`). See `README.md` and `architecture_spec.md` for product details, and the `Makefile` for the canonical commands.

### Environment notes (already handled by the startup update script)
- **Flutter** is installed at `/opt/flutter` and symlinked to `/usr/local/bin/flutter` and `/usr/local/bin/dart` (on `PATH` for all shells). The client requires **Dart >= 3.12** (Flutter `3.44.x`); older stable Flutter (e.g. 3.32) fails `pub get` because of `sqflite_common_ffi_web`.
- The server uses a Python venv at `server/venv` (created via the system `python3.12-venv` package). Run server commands through `server/venv/bin/...`.

### Running services (commands live in the `Makefile`)
- **Server** (`make server`): Uvicorn on `:8080` with `--reload`. Creates `server/transactions.db` (SQLite) automatically; no DB setup needed. Health: `curl http://127.0.0.1:8080/health`.
- **Client** (`make client`): `flutter run -d chrome --web-port 9090`. In a headless cloud VM prefer the web-server device so a browser can attach to it:
  `cd client && flutter run -d web-server --web-port 9090 --web-hostname 0.0.0.0 --dart-define=SERVER_HOST=127.0.0.1`
  Pass `--dart-define=SERVER_HOST=127.0.0.1` for local dev — the default host is the Tailscale shortname `akhilesh`, which is unreachable here.

### Ollama (optional AI enrichment) — NOT installed
- The server enriches transactions by calling **Ollama** (`qwen3:8b`, port `11434`). Ollama is **not** installed in this environment.
- Without Ollama the app is fully usable: the client parses entries locally (regex) and persists/displays them offline. Server `/api/v1/sync` still persists transactions, but enrichment marks them `sync_status: "failed"`, and `/api/v1/import` is a no-op (it depends on the LLM to parse the file). This degradation is expected, not a bug.
- To exercise the AI path, run `ollama serve` + `ollama pull qwen3:8b` separately (heavy; CPU inference of an 8B model is very slow).

### Tests / lint
- `make test-client` (`flutter test`): one pre-existing failure in `regex_parser_test.dart` ("reparse should clear enrichment fields") — the amount parser extracts `5` from "Zee5". This is an app-logic issue unrelated to environment setup.
- `cd client && flutter analyze`: reports 2 pre-existing `info`-level lint notes in `lib/main.dart` (sqflite imports); no errors.
- `make test-server`: requires a running server; the `import` portion times out without Ollama (see above).
