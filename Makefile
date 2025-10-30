# Project Sync Tool Makefile
# Provides traditional Unix installation workflow

# Variables
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
SHAREDIR = $(PREFIX)/share/project-sync
MANDIR = $(PREFIX)/share/man/man1
CONFIGDIR = $(HOME)/.config/project-sync

# Tool information
# Project configuration
NAME = psync
VERSION = 0.1

# Installation targets
.PHONY: all install install-user uninstall uninstall-user update clean clean-all test install-bats test-only check-deps help

all: help

# Install system-wide (requires sudo)
install: 
	@echo "Installing $(NAME) system-wide to $(PREFIX)..."
	install -d $(BINDIR)
	install -d $(SHAREDIR)/tests
	install -d $(MANDIR)
	
	# Install main script and unified interface
	install -m 755 psync.sh $(BINDIR)/psync.sh
	install -m 755 psync $(BINDIR)/psync
	install -m 644 psync.conf $(BINDIR)/psync.conf
	
	# Install test suite
	cp -r tests/ $(SHAREDIR)/tests/
	install -m 755 test.sh $(SHAREDIR)/tests/
	
	# Install documentation
	install -m 644 README.md $(SHAREDIR)/
	
	@echo "✓ Installation complete!"
	@echo "Run 'psync --help' to get started"

# Install for current user only
install-user:
	@echo "Installing $(NAME) for current user..."
	install -d $(HOME)/.local/bin
	install -d $(HOME)/.local/share/project-sync/tests
	install -d $(CONFIGDIR)
	
	# Install main script and unified interface
	install -m 755 psync.sh $(HOME)/.local/bin/psync.sh
	install -m 755 psync $(HOME)/.local/bin/psync
	install -m 644 psync.conf $(HOME)/.local/bin/psync.conf
	
	# Install test suite
	cp -r tests/ $(HOME)/.local/share/project-sync/tests/
	install -m 755 test.sh $(HOME)/.local/share/project-sync/tests/
	
	# Create default config if it doesn't exist
	@if [ ! -f $(CONFIGDIR)/template.csv ]; then \
		echo "Creating default template..."; \
		echo "# Project,Experiment,Run,Analysis,Source,Destination,Option" > $(CONFIGDIR)/template.csv; \
		echo "example,exp_001,run_001,analysis,/source/path,dest_folder,copy" >> $(CONFIGDIR)/template.csv; \
	fi
	
	@echo "✓ User installation complete!"
	@echo "Add ~/.local/bin to your PATH if not already done"
	@echo "export PATH=\"$$HOME/.local/bin:$$PATH\""

# Uninstall system-wide
uninstall:
	@echo "Uninstalling $(NAME)..."
	rm -f $(BINDIR)/psync.sh $(BINDIR)/psync $(BINDIR)/psync.conf
	rm -rf $(SHAREDIR)
	@echo "✓ Uninstalled (config files in ~/.config/project-sync preserved)"

# Uninstall user installation
uninstall-user:
	@echo "Uninstalling $(NAME) for current user..."
	rm -f $(HOME)/.local/bin/psync.sh $(HOME)/.local/bin/psync $(HOME)/.local/bin/psync.conf
	rm -rf $(HOME)/.local/share/project-sync
	@echo "✓ User installation uninstalled (config files in ~/.config/project-sync preserved)"

# Update from git repository and reinstall
update:
	@echo "Updating $(NAME) from git repository..."
	@if [ ! -d ".git" ]; then \
		echo "ERROR: Not a git repository. Cannot update."; \
		echo "This command requires the project to be cloned from git."; \
		exit 1; \
	fi
	@echo "Fetching latest changes..."
	git fetch origin
	@echo "Pulling updates..."
	git pull origin main
	@echo "Reinstalling updated version..."
	@if [ -f "$(HOME)/.local/bin/$(NAME)" ]; then \
		echo "Detected user installation. Updating user installation..."; \
		$(MAKE) install-user; \
	elif [ -f "$(BINDIR)/$(NAME)" ]; then \
		echo "Detected system installation. Updating system installation..."; \
		$(MAKE) install; \
	else \
		echo "No existing installation detected. Installing for current user..."; \
		$(MAKE) install-user; \
	fi
	@echo "✓ Update complete!"

# Run tests
test: install-bats
	@echo "Running test suite..."
	./test.sh

# Install bats testing framework if not present
install-bats:
	@if [ ! -x ./bats-core/bin/bats ]; then \
		echo "Installing bats-core for bash testing..."; \
		if [ -d "bats-core" ]; then \
			echo "bats-core directory exists. Updating..."; \
			cd bats-core && git pull origin master && cd ..; \
		else \
			echo "Cloning bats-core repository..."; \
			git clone https://github.com/bats-core/bats-core.git; \
		fi; \
		chmod +x bats-core/bin/bats; \
		if [ ! -L "bats" ]; then \
			ln -s bats-core/bin/bats bats; \
			echo "Created symbolic link 'bats' for easier access"; \
		fi; \
		echo "bats-core installation completed successfully!"; \
		echo ""; \
		echo "Usage:"; \
		echo "  Run all tests:     ./bats-core/bin/bats tests/"; \
		echo "  Run specific test: ./bats-core/bin/bats tests/test_psync.bats"; \
		echo "  Or use symlink:    ./bats tests/"; \
		echo ""; \
		echo "Test files location: tests/"; \
	else \
		echo "bats already installed"; \
	fi

# Run tests without installation (for CI/development)
test-only:
	@if [ ! -x ./bats-core/bin/bats ]; then \
		echo "ERROR: bats not installed. Run 'make install-bats' first."; \
		exit 1; \
	fi
	@echo "Running tests with existing bats installation..."
	./bats-core/bin/bats tests/test_psync.bats

# Check test dependencies
check-deps:
	@echo "Checking dependencies..."
	@command -v bash >/dev/null 2>&1 || { echo "ERROR: bash not found"; exit 1; }
	@command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync not found"; exit 1; }
	@command -v tar >/dev/null 2>&1 || { echo "ERROR: tar not found"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "WARNING: git not found (needed for bats install)"; }
	@echo "✓ All dependencies satisfied"

# Create distribution tarball
dist:
	@echo "Creating distribution tarball..."
	mkdir -p dist/$(NAME)-$(VERSION)
	cp -r * dist/$(NAME)-$(VERSION)/ 2>/dev/null || true
	cd dist && tar -czf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/
	rm -rf dist/$(NAME)-$(VERSION)
	@echo "✓ Created dist/$(NAME)-$(VERSION).tar.gz"

# Clean build artifacts
clean:
	rm -rf dist/
	rm -f *.log
	rm -rf bats-core/
	rm -rf project*
	rm -rf logs*

# Clean everything including installed files
clean-all: clean
	rm -f $(HOME)/.local/bin/psync.sh $(HOME)/.local/bin/psync $(HOME)/.local/bin/psync.conf
	rm -rf $(HOME)/.local/share/project-sync

# Help target
help:
	@echo "Project Sync Tool - Make targets:"
	@echo ""
	@echo "  install         Install system-wide (requires sudo)"
	@echo "  install-user    Install for current user only"
	@echo "  uninstall       Remove system-wide installation"
	@echo "  uninstall-user  Remove user installation"
	@echo "  update          Update from git and reinstall"
	@echo "  test            Install bats and run test suite"
	@echo "  test-only       Run tests without installing bats"
	@echo "  install-bats    Install bats testing framework"
	@echo "  check-deps      Check system dependencies"
	@echo "  dist            Create distribution tarball"
	@echo "  clean           Clean build artifacts"
	@echo "  clean-all       Clean everything including installed files"
	@echo "  help            Show this help"
	@echo ""
	@echo "Quick start:"
	@echo "  make check-deps      # Check dependencies"
	@echo "  make test           # Install bats and run tests"
	@echo "  make install-user   # Install for current user"
	@echo "  make update         # Update from git and reinstall"
	@echo "  make uninstall-user # Remove user installation"
