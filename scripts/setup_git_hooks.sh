#!/usr/bin/env bash
# Install the repository-managed git hooks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

git config --local core.hooksPath .githooks
chmod +x .githooks/*

echo "Git hooks installed. core.hooksPath is now .githooks."
