#!/usr/bin/env bash
# ==============================================================================
# CineData Analytics — Environment Setup Script (setup.sh)
# ==============================================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"

echo -e "\n${C_BOLD}${C_CYAN}📊 [CineData Pipeline] Setting up Data Engineering environment...${C_RESET}\n"

# Verify CSV datasets availability in data/landing
LANDING_DIR="$PROJECT_ROOT/../data/landing"
if [ ! -f "$LANDING_DIR/credits_and_tags_IMDB_TMDB.csv" ]; then
    DATA_SYNC_SCRIPT="$PROJECT_ROOT/../scripts/data_sync.sh"
    if [ -f "$DATA_SYNC_SCRIPT" ]; then
        echo -e "${C_YELLOW}⚠️  CSV datasets not found in data/landing. Extracting from chunks via data_sync.sh...${C_RESET}"
        bash "$DATA_SYNC_SCRIPT" deserialize
    fi
fi

if command -v uv &> /dev/null; then
    echo -e "${C_GREEN}✓ Using uv for dependency management...${C_RESET}"
    cd "$PROJECT_ROOT"
    uv sync --extra dev
    echo -e "${C_GREEN}✓ Data pipeline environment successfully set up with uv!${C_RESET}"
elif command -v python3 &> /dev/null; then
    echo -e "${C_YELLOW}⚠️  'uv' not found. Falling back to python3 -m venv...${C_RESET}"
    cd "$PROJECT_ROOT"
    python3 -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install .[dev]
    echo -e "${C_GREEN}✓ Data pipeline environment successfully set up with pip!${C_RESET}"
else
    echo -e "${C_RED}❌ Error: Python or uv runtime not found.${C_RESET}"
    exit 1
fi
