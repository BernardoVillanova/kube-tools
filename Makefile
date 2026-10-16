.PHONY: help install dry-run doctor test lint uninstall

help:
	@echo "kube-tools Makefile targets:"
	@echo "  make install    - Run the interactive kube-tools installer"
	@echo "  make dry-run    - Run the installer in read-only simulation mode"
	@echo "  make doctor     - Run environment, PATH, and SHA-256 health diagnostics"
	@echo "  make test       - Run the automated sandbox test suite"
	@echo "  make lint       - Validate bash syntax and run shellcheck (if installed)"
	@echo "  make uninstall  - Rollback all kube-tools binaries and shell configurations"

install:
	./install.sh

dry-run:
	./install.sh --dry-run

doctor:
	./install.sh --doctor

test:
	bash ./tests/test_installer.sh

lint:
	bash -n ./install.sh
	bash -n ./tests/test_installer.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck ./install.sh ./tests/test_installer.sh; \
		echo "ShellCheck passed!"; \
	else \
		echo "bash -n passed (install shellcheck for deeper static analysis)"; \
	fi

uninstall:
	./install.sh --uninstall
