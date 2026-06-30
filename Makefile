.PHONY: setup server client test test-client test-server test-server-unit health ios-devices ios-release android-apk

setup:
	cd server && python3 -m venv venv
	cd server && ./venv/bin/pip install -r requirements.txt
	cd client && flutter pub get

server:
	cd server && ./venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080 --reload

client:
	cd client && flutter run -d chrome --web-port 9090 2>&1

ios-devices:
	cd client && flutter devices

# Usage: make ios-release DEVICE="Akhilesh's iPhone (wireless)"
# Optional: SERVER_HOST=hostname seeds the in-app default on first launch only
DEVICE ?=
SERVER_HOST ?=

ios-release:
	@if [ -z "$(DEVICE)" ]; then \
		echo 'Usage: make ios-release DEVICE="Your iPhone Name"'; \
		echo 'Run make ios-devices to list connected phones.'; \
		exit 1; \
	fi
	@if [ -n "$(SERVER_HOST)" ]; then \
		cd client && flutter run --release -d "$(DEVICE)" --dart-define=SERVER_HOST=$(SERVER_HOST); \
	else \
		cd client && flutter run --release -d "$(DEVICE)"; \
	fi

# Usage: make android-apk [VERSION=1.2.0] [SERVER_HOST=hostname]
# VERSION sets the Android versionName and a monotonic versionCode so installs
# upgrade cleanly instead of conflicting. Defaults to the pubspec.yaml version.
VERSION ?=

android-apk:
	@VERSION_ARGS=""; \
	if [ -n "$(VERSION)" ]; then \
		CLEAN=$$(echo "$(VERSION)" | sed -E 's/^v//; s/[-+].*$$//'); \
		MAJOR=$$(echo "$$CLEAN" | cut -d. -f1); \
		MINOR=$$(echo "$$CLEAN" | cut -d. -f2); \
		PATCH=$$(echo "$$CLEAN" | cut -d. -f3); \
		MAJOR=$${MAJOR:-0}; MINOR=$${MINOR:-0}; PATCH=$${PATCH:-0}; \
		CODE=$$((MAJOR * 1000000 + MINOR * 1000 + PATCH)); \
		VERSION_ARGS="--build-name=$$CLEAN --build-number=$$CODE"; \
		echo "Building versionName=$$CLEAN versionCode=$$CODE"; \
	fi; \
	if [ -n "$(SERVER_HOST)" ]; then \
		cd client && flutter build apk --release $$VERSION_ARGS --dart-define=SERVER_HOST=$(SERVER_HOST); \
	else \
		cd client && flutter build apk --release $$VERSION_ARGS; \
	fi
	mkdir -p dist
	cp client/build/app/outputs/flutter-apk/app-release.apk dist/TapEx-release.apk
	@echo ""
	@echo "APK ready to share: dist/TapEx-release.apk"
	@ls -lh dist/TapEx-release.apk

test: test-client

test-client:
	cd client && flutter test

test-server:
	cd server && ./venv/bin/python test_server.py

test-server-unit:
	cd server && ./venv/bin/python -m unittest test_llm_client.py test_categories.py test_enrichment_config.py

health:
	@curl -s http://127.0.0.1:8080/health | python3 -m json.tool || echo "Server not running. Start with: make server"
