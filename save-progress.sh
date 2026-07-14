#!/usr/bin/env bash
# Safely commits and pushes current progress to GitHub.
# Run this from the ROOT of your macden-website repo, in Git Bash.
#
# Usage: bash save-progress.sh "your commit message here"

set -e

if [ -z "$1" ]; then
  echo "Please provide a commit message."
  echo "Example: bash save-progress.sh \"Add price check and price history pages\""
  exit 1
fi

echo "--- Checking status ---"
git status

echo ""
echo "--- Safety check: making sure .env is not about to be committed ---"
if git status --porcelain | grep -q "server/.env$"; then
  echo "WARNING: server/.env is showing up as a change to commit."
  echo "This file contains real secrets and should never be pushed."
  echo "Stopping here — check your .gitignore before continuing."
  exit 1
else
  echo "OK — .env is not being tracked. Safe to continue."
fi

echo ""
echo "--- Adding changes ---"
git add .

echo ""
echo "--- Committing ---"
git commit -m "$1"

echo ""
echo "--- Pushing to GitHub ---"
git push

echo ""
echo "Done. Progress saved to GitHub."
