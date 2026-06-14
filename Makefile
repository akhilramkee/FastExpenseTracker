.PHONY: setup server client test test-client test-server health

setup:
	cd server && python3 -m venv venv
	cd server && ./venv/bin/pip install -r requirements.txt
	cd client && flutter pub get

server:
	cd server && ./venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080 --reload

client:
	cd client && flutter run -d chrome --web-port 9090 2>&1

test: test-client

test-client:
	cd client && flutter test

test-server:
	cd server && ./venv/bin/python test_server.py

health:
	@curl -s http://127.0.0.1:8080/health | python3 -m json.tool || echo "Server not running. Start with: make server"
