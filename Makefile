# Makefile for axorc helper

# Define the output binary name
BINARY_NAME = axorc
UNIVERSAL_BINARY_PATH = ./$(BINARY_NAME)

# Build and ad-hoc sign a universal local binary.
all:
	@echo "Cleaning old binary..."
	rm -f $(UNIVERSAL_BINARY_PATH)
	./scripts/build-universal-binary.sh $(UNIVERSAL_BINARY_PATH)
	@echo "Build complete: $(UNIVERSAL_BINARY_PATH)"
	@ls -l $(UNIVERSAL_BINARY_PATH)


clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -f $(UNIVERSAL_BINARY_PATH)
	@echo "Clean complete."

verify-release-packaging:
	@test -n "$(VERSION)" || (echo "VERSION is required" >&2; exit 2)
	./scripts/verify-release-packaging.sh "$(VERSION)"

# Format code with SwiftFormat
format:
	@echo "Formatting code with SwiftFormat..."
	swiftformat .
	@echo "Code formatting complete."

# Check code formatting (for CI)
format-check:
	@echo "Checking code formatting with SwiftFormat..."
	swiftformat --lint .
	@echo "Code formatting check complete."

# Lint code with SwiftLint
lint:
	@echo "Linting code with SwiftLint..."
	swiftlint lint --strict
	@echo "Code linting complete."

native-only:
	@bash scripts/test-native-ax-only.sh
	@bash scripts/test-native-ax-only-policy.sh

.PHONY: test-commander-dependency
test-commander-dependency:
	python3 scripts/test-commander-dependency.py

.PHONY: test-universal-binary-mode
test-universal-binary-mode:
	@bash scripts/test-universal-binary-mode.sh

.PHONY: test-homebrew-formula
test-homebrew-formula:
	python3 scripts/test-homebrew-formula.py

# Run formatting, linting, native-only policy, dependency, and packaging checks
check: format-check lint native-only test-commander-dependency test-universal-binary-mode test-homebrew-formula
	@echo "All code checks complete."

# Default target
.DEFAULT_GOAL := all
