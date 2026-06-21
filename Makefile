.PHONY: setup server client test test-client test-server health ios-devices ios-release android-apk

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
# Optional: SERVER_HOST=akhilesh (default)
DEVICE ?=
SERVER_HOST ?= akhilesh

ios-release:
	@if [ -z "$(DEVICE)" ]; then \
		echo 'Usage: make ios-release DEVICE="Your iPhone Name"'; \
		echo 'Run make ios-devices to list connected phones.'; \
		exit 1; \
	fi
	cd client && flutter run --release -d "$(DEVICE)" --dart-define=SERVER_HOST=$(SERVER_HOST)

android-apk:
	cd client && flutter build apk --release --dart-define=SERVER_HOST=$(SERVER_HOST)
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

health:
	@curl -s http://127.0.0.1:8080/health | python3 -m json.tool || echo "Server not running. Start with: make server"
