#!/bin/bash

# Fix missing refresh token for headless daemon

set -e

echo "=== Refresh Token Fix Script ==="
echo
echo "This script will help you get a refresh token for headless operation."
echo

# Check if we're on a headless system
if [ -z "$DISPLAY" ] && ! command -v xdg-open &> /dev/null; then
    echo "⚠️  WARNING: This appears to be a headless system."
    echo "   You cannot authorize here - you need a browser."
    echo
    echo "   Solution: Run this on a machine with a browser, then copy the token file."
    echo
    echo "   Steps:"
    echo "   1. Run this script on a machine with a browser"
    echo "   2. Copy ~/.oauth2.rkt/tokens to this server"
    echo "   3. Copy ~/.oauth2.rkt/preferences to this server"
    echo
    exit 1
fi

echo "Step 1: Check current token status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
racket src/diagnose-token.rkt 2>&1 || echo "(Error is expected if token is corrupted)"
echo

echo "Step 2: Revoke existing Google authorization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "IMPORTANT: You must manually revoke your existing authorization."
echo
echo "1. Open this URL in your browser:"
echo "   https://myaccount.google.com/permissions"
echo
echo "2. Find your OAuth app in the list"
echo "3. Click 'Remove Access' or 'Revoke'"
echo
read -p "Press Enter after you've revoked the app authorization..."
echo

echo "Step 3: Delete old token file"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOKEN_FILE="$HOME/.oauth2.rkt/tokens"
if [ -f "$TOKEN_FILE" ]; then
    echo "Backing up: $TOKEN_FILE.backup"
    cp "$TOKEN_FILE" "$TOKEN_FILE.backup"
    echo "Deleting: $TOKEN_FILE"
    rm "$TOKEN_FILE"
    echo "✓ Old token deleted"
else
    echo "No token file found (this is fine)"
fi
echo

echo "Step 4: Start fresh authorization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running authorization flow..."
echo "This will open your browser and request access_type=offline"
echo
racket src/force-reauth.rkt
echo

echo "Step 5: Verify refresh token"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
racket src/diagnose-token.rkt
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Done!"
echo
echo "If you see '✓ Refresh token is present' above, you're all set!"
echo "Your daemon can now run indefinitely on a headless server."
echo
echo "To copy to a server:"
echo "  scp ~/.oauth2.rkt/tokens SERVER:~/.oauth2.rkt/tokens"
echo "  scp ~/.oauth2.rkt/preferences SERVER:~/.oauth2.rkt/preferences"
