# ==============================================================================
# CineRocket Platform — Monorepo Orchestration Makefile
# ==============================================================================

.PHONY: help setup-all setup-data setup-core setup-ai run-core run-ai test-all lint-all

help:
	@echo "======================================================================"
	@echo " CineRocket Platform — Monorepo Management Commands"
	@echo "======================================================================"
	@echo "  make setup-all       - Set up environments for all modules"
	@echo "  make setup-data      - Set up Data Pipeline (PySpark / uv)"
	@echo "  make setup-core      - Set up Core Platform (FastAPI + React 19)"
	@echo "  make setup-ai        - Set up GenAI Movie Agent (LangGraph + React 19)"
	@echo ""
	@echo "  make run-core        - Launch Core Platform (Backend + Frontend)"
	@echo "  make run-ai          - Launch GenAI Movie Agent (Backend + Frontend)"
	@echo ""
	@echo "  make test-all        - Run automated tests across modules"
	@echo "  make lint-all        - Run linters across Python and TypeScript code"
	@echo "======================================================================"

# ------------------------------------------------------------------------------
# Environment Setup Targets
# ------------------------------------------------------------------------------

setup-all: setup-data setup-core setup-ai
	@echo "✓ All CineRocket modules successfully initialized!"

setup-data:
	@echo "==> Setting up Data Pipeline..."
	@cd data-pipeline && ./setup.sh

setup-core:
	@echo "==> Setting up Core Platform..."
	@cd core-platform && ./setup.sh --no-launch || (cd core-platform/backend && uv sync --all-extras && cd ../frontend && bun install)

setup-ai:
	@echo "==> Setting up GenAI Assistant..."
	@cd ai-assistant && (cd backend && uv sync --all-extras && cd ../frontend && bun install)

# ------------------------------------------------------------------------------
# Execution Targets
# ------------------------------------------------------------------------------

run-core:
	@echo "==> Launching CineFlow Core Platform..."
	@cd core-platform && ./setup.sh

run-ai:
	@echo "==> Launching CineRocket GenAI Movie Agent..."
	@cd ai-assistant && ./setup.sh

# ------------------------------------------------------------------------------
# Quality & Testing Targets
# ------------------------------------------------------------------------------

test-all:
	@echo "==> Running Core Platform backend tests..."
	@cd core-platform/backend && uv run python -m pytest
	@echo "==> Running Core Platform frontend tests..."
	@cd core-platform/frontend && bun run test
	@echo "==> Running GenAI Assistant backend tests..."
	@cd ai-assistant/backend && uv run python -m pytest
	@echo "✓ All tests executed successfully!"

lint-all:
	@echo "==> Linting Python code..."
	@cd core-platform/backend && uv run ruff check .
	@cd ai-assistant/backend && uv run ruff check .
	@echo "==> Linting TypeScript / React code..."
	@cd core-platform/frontend && bun run lint
	@cd ai-assistant/frontend && bun run lint
	@echo "✓ All linters passed!"
