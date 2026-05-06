.PHONY: help sidecar sidecar-install sidecar-test app app-generate app-release install smoke clean services-install services-uninstall services-restart services-status services-logs sudoers-install sudoers-uninstall

PYTHON ?= python3
SIDECAR_VENV := sidecar/.venv
SIDECAR_PY := $(SIDECAR_VENV)/bin/python
APP_DERIVED := app/.build
APP_PRODUCT := $(APP_DERIVED)/Build/Products/Release/GPSMock.app

TUNNELD_LABEL := com.louisdeng.gpsmock.tunneld
SIDECAR_LABEL := com.louisdeng.gpsmock.sidecar
TUNNELD_TEMPLATE := launchd/$(TUNNELD_LABEL).plist
SIDECAR_TEMPLATE := launchd/$(SIDECAR_LABEL).plist
TUNNELD_DEST := /Library/LaunchDaemons/$(TUNNELD_LABEL).plist
SIDECAR_DEST := $(HOME)/Library/LaunchAgents/$(SIDECAR_LABEL).plist
SUDOERS_FILE := /etc/sudoers.d/gpsmock

help:
	@echo "make sidecar-install     Create sidecar venv and install deps"
	@echo "make sidecar             Run the FastAPI sidecar on 127.0.0.1:5555"
	@echo "make sidecar-test        Run sidecar pytest suite"
	@echo "make app-generate        Generate app/GPSMock.xcodeproj from project.yml"
	@echo "make app                 Open the Xcode project (regenerates if missing)"
	@echo "make app-release         Build a Release .app into app/.build"
	@echo "make install             Build Release, install /Applications/GPSMock.app, set up sudoers"
	@echo "make sudoers-install     Add a passwordless-sudo entry so the app can spawn tunneld"
	@echo "make sudoers-uninstall   Remove the sudoers entry"
	@echo "make services-install    (Optional) install launchd plists for boot-time tunneld + sidecar"
	@echo "make services-uninstall  Stop and remove the launchd plists"
	@echo "make services-restart    Restart both background services"
	@echo "make services-status     Show launchctl print for both services"
	@echo "make services-logs       tail -F the tunneld + sidecar logs"
	@echo "make smoke               Curl the sidecar /health and /device"
	@echo "make clean               Remove venv, caches, and generated Xcode project"

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

app-release: app/GPSMock.xcodeproj
	cd app && xcodebuild \
		-project GPSMock.xcodeproj \
		-scheme GPSMock \
		-configuration Release \
		-derivedDataPath .build \
		-quiet \
		build

install: app-release sudoers-install
	rm -rf /Applications/GPSMock.app
	cp -R $(APP_PRODUCT) /Applications/GPSMock.app
	@# Stamp this checkout's path into the installed bundle so the app can find
	@# sidecar/.venv at runtime regardless of where the user cloned the repo.
	@plutil -remove GPSMockRepoPath /Applications/GPSMock.app/Contents/Info.plist 2>/dev/null || true
	@plutil -insert GPSMockRepoPath -string "$(abspath .)" /Applications/GPSMock.app/Contents/Info.plist
	@# Re-seal the bundle: editing Info.plist after xcodebuild's adhoc sign
	@# breaks the signature, which makes TCC refuse Location/Privacy grants.
	@codesign --force --sign - --options runtime \
		--entitlements app/Resources/GPSMock.entitlements \
		/Applications/GPSMock.app
	@echo "✅ Installed /Applications/GPSMock.app — launch via Spotlight."
	@echo "   The app will spawn tunneld + sidecar on launch and clean them up on quit."
	@echo "   Bundled GPSMockRepoPath: $(abspath .)"

sudoers-install: $(SIDECAR_VENV)
	@printf "%s ALL=(ALL) NOPASSWD: %s -m pymobiledevice3 remote tunneld\n" "$(USER)" "$(abspath $(SIDECAR_PY))" | \
		sudo tee $(SUDOERS_FILE) > /dev/null
	@sudo chmod 440 $(SUDOERS_FILE)
	@sudo chown root:wheel $(SUDOERS_FILE)
	@if ! sudo visudo -c > /dev/null 2>&1; then sudo rm -f $(SUDOERS_FILE); echo "❌ Sudoers validation failed; reverted."; exit 1; fi
	@echo "✅ Passwordless sudo for tunneld installed at $(SUDOERS_FILE)"

sudoers-uninstall:
	-sudo rm -f $(SUDOERS_FILE)
	@echo "✅ Sudoers entry removed."

services-install: $(SIDECAR_VENV)
	@echo "→ Stop any manual tunneld/sidecar before installing services."
	@mkdir -p $(HOME)/Library/Logs/GPSMock $(HOME)/Library/LaunchAgents
	@sudo mkdir -p /var/log/gpsmock
	sed -e 's|__SIDECAR_PY__|$(abspath $(SIDECAR_PY))|g' \
	    -e 's|__USER_HOME__|$(HOME)|g' \
	    -e 's|__REPO_DIR__|$(abspath .)|g' \
	    $(SIDECAR_TEMPLATE) > $(SIDECAR_DEST)
	sed -e 's|__SIDECAR_PY__|$(abspath $(SIDECAR_PY))|g' \
	    -e 's|__USER_HOME__|$(HOME)|g' \
	    $(TUNNELD_TEMPLATE) | sudo tee $(TUNNELD_DEST) > /dev/null
	sudo chown root:wheel $(TUNNELD_DEST)
	sudo chmod 644 $(TUNNELD_DEST)
	-launchctl bootout gui/$$(id -u) $(SIDECAR_DEST) 2>/dev/null
	launchctl bootstrap gui/$$(id -u) $(SIDECAR_DEST)
	-sudo launchctl bootout system $(TUNNELD_DEST) 2>/dev/null
	sudo launchctl bootstrap system $(TUNNELD_DEST)
	@echo "✅ Services running. They auto-start on boot/login."
	@echo "   Logs:    make services-logs"
	@echo "   Status:  make services-status"
	@echo "   Smoke:   make smoke"

services-uninstall:
	-launchctl bootout gui/$$(id -u) $(SIDECAR_DEST) 2>/dev/null
	-sudo launchctl bootout system $(TUNNELD_DEST) 2>/dev/null
	-rm -f $(SIDECAR_DEST)
	-sudo rm -f $(TUNNELD_DEST)
	@echo "✅ Services unloaded and removed."

services-restart:
	-launchctl kickstart -k gui/$$(id -u)/$(SIDECAR_LABEL)
	-sudo launchctl kickstart -k system/$(TUNNELD_LABEL)
	@echo "✅ Services restarted."

services-status:
	@echo "── sidecar (LaunchAgent, user)"
	@launchctl print gui/$$(id -u)/$(SIDECAR_LABEL) 2>/dev/null | sed -n '1,12p' || echo "  not loaded"
	@echo
	@echo "── tunneld (LaunchDaemon, root)"
	@sudo launchctl print system/$(TUNNELD_LABEL) 2>/dev/null | sed -n '1,12p' || echo "  not loaded"

services-logs:
	@echo "── tail -F sidecar + tunneld logs (Ctrl+C to stop)"
	@tail -F $(HOME)/Library/Logs/GPSMock/sidecar.log $(HOME)/Library/Logs/GPSMock/sidecar.err /var/log/gpsmock/tunneld.log /var/log/gpsmock/tunneld.err 2>/dev/null

smoke:
	@echo "→ /health"
	@curl -sf http://127.0.0.1:5555/health || (echo "sidecar down — run 'make sidecar' or 'make services-install'"; exit 1)
	@echo
	@echo "→ /device"
	@curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:5555/device

clean:
	rm -rf $(SIDECAR_VENV) sidecar/.pytest_cache sidecar/.ruff_cache sidecar/**/__pycache__
	rm -rf app/GPSMock.xcodeproj $(APP_DERIVED)
