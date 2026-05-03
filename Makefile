.PHONY: help sidecar sidecar-install sidecar-test app app-generate smoke clean

PYTHON ?= python3
SIDECAR_VENV := sidecar/.venv
SIDECAR_PY := $(SIDECAR_VENV)/bin/python

help:
	@echo "make sidecar-install  Create sidecar venv and install deps"
	@echo "make sidecar          Run the FastAPI sidecar on 127.0.0.1:5555"
	@echo "make sidecar-test     Run sidecar pytest suite"
	@echo "make app-generate     Generate app/GPSMock.xcodeproj from project.yml"
	@echo "make app              Open the Xcode project (regenerates if missing)"
	@echo "make smoke            Curl the sidecar /health and /device"
	@echo "make clean            Remove venv, caches, and generated Xcode project"

$(SIDECAR_VENV):
	$(PYTHON) -m venv $(SIDECAR_VENV)

sidecar-install: $(SIDECAR_VENV)
	$(SIDECAR_PY) -m pip install --upgrade pip
	$(SIDECAR_PY) -m pip install -e 'sidecar[dev]'

sidecar: $(SIDECAR_VENV)
	$(SIDECAR_PY) -m gpsmock_sidecar

sidecar-test: $(SIDECAR_VENV)
	$(SIDECAR_PY) -m pytest sidecar/tests -v

app/GPSMock.xcodeproj: app/project.yml
	cd app && xcodegen generate

app-generate:
	cd app && xcodegen generate

app: app/GPSMock.xcodeproj
	open app/GPSMock.xcodeproj

smoke:
	@echo "→ /health"
	@curl -sf http://127.0.0.1:5555/health || (echo "sidecar down — run 'make sidecar'"; exit 1)
	@echo
	@echo "→ /device"
	@curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:5555/device

clean:
	rm -rf $(SIDECAR_VENV) sidecar/.pytest_cache sidecar/.ruff_cache sidecar/**/__pycache__
	rm -rf app/GPSMock.xcodeproj
