#!/bin/bash
# task-router.sh — Wrapper that delegates to Python implementation for performance
# Python version is ~2.5x faster (28ms vs 71ms)
exec python3 "$(dirname "$0")/task-router.py" "$@"
