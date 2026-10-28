PLUGIN_ID := arch.ramfree
PLUGIN_DIR := $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)
BINDIR ?= $(HOME)/.local/bin

HELPER_DEST := /usr/local/libexec/ramfree-helper
POLICY_DEST := /usr/share/polkit-1/actions/org.omarchy.ramfree.policy

.PHONY: all install uninstall install-helper uninstall-helper check

all:
	@echo "targets: install, uninstall (user)  |  install-helper, uninstall-helper (sudo)  |  check"

install:
	mkdir -p $(PLUGIN_DIR)/bin
	install -m644 plugin/manifest.json plugin/Panel.qml plugin/RingGauge.qml plugin/StatBar.qml plugin/Model.js $(PLUGIN_DIR)/
	install -m755 plugin/bin/ramfree $(PLUGIN_DIR)/bin/ramfree
	install -Dm755 plugin/bin/ramfree $(BINDIR)/ramfree
	@omarchy-shell -q shell rescanPlugins; sleep 1
	@omarchy bar put $(PLUGIN_ID) --before omarchy.monitor >/dev/null 2>&1 || omarchy plugin enable $(PLUGIN_ID) --section right || true
	@echo "installed $(PLUGIN_ID) to $(PLUGIN_DIR) and $(BINDIR)/ramfree"

uninstall:
	-omarchy plugin disable $(PLUGIN_ID)
	rm -rf $(PLUGIN_DIR)
	rm -f $(BINDIR)/ramfree

# Root part for depths 3-5. Allows the active local session to run the helper
# without a password (the helper accepts only "3", "4" or "5").
install-helper:
	install -Dm755 -o root -g root helper/ramfree-helper $(HELPER_DEST)
	install -Dm644 -o root -g root helper/org.omarchy.ramfree.policy $(POLICY_DEST)
	@echo "installed $(HELPER_DEST) and $(POLICY_DEST)"

uninstall-helper:
	rm -f $(HELPER_DEST) $(POLICY_DEST)

check:
	bash -n plugin/bin/ramfree
	bash -n helper/ramfree-helper
	omarchy plugin validate plugin
