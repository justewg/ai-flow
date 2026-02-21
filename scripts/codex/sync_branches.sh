#!/usr/bin/env bash
set -euo pipefail

git fetch origin
git checkout main
git pull --ff-only origin main
git checkout development
git merge --ff-only main
git push origin development
git status --short --branch

