#!/usr/bin/env bash
# scripts/create-cert.sh
# One-shot: create a stable self-signed code-signing certificate and import
# it into the user's login keychain. Used by the project to sign every
# build with the same identity, so macOS TCC (Screen Recording, etc.)
# treats consecutive rebuilds as the same app and doesn't re-prompt.
#
# Why this exists: Apple's free Personal Team has a known glitch where
# certs download without their private key ("Not in Keychain" status),
# and the only clean way to revoke an orphan is via developer.apple.com
# which is gated to the paid Developer Program ($99/yr). This script
# bypasses Apple entirely — signs locally, stays consistent forever
# (or until the cert expires in 2035).
#
# The cert is technically "not trusted" by Gatekeeper (self-signed roots
# never are), but codesign accepts it for signing without trust — trust
# only matters when verifying signatures on someone else's Mac, which
# is irrelevant for a personal app that we're never distributing.
#
# Run once. Idempotent: safe to re-run, will replace the existing cert.

set -euo pipefail

CERT_NAME="Dial Local Dev"
DAYS=3650  # ~10 years
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "→ Generating self-signed code-signing cert ($CERT_NAME)"
cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no

[dn]
CN = $CERT_NAME

[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# Use macOS's built-in LibreSSL (/usr/bin/openssl) — its PKCS12 output
# is keychain-native. Homebrew's openssl 3.x produces PKCS12 that macOS
# silently strips the private key from on import.
/usr/bin/openssl req -new -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" \
  -out "$TMP/cert.pem" \
  -days "$DAYS" \
  -config "$TMP/openssl.cnf" \
  -extensions v3 \
  >/dev/null 2>&1

/usr/bin/openssl pkcs12 -export \
  -inkey "$TMP/key.pem" \
  -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" \
  -name "$CERT_NAME" \
  -password pass:dial \
  >/dev/null 2>&1

echo "→ Removing any prior '$CERT_NAME' cert (safe if absent)"
security delete-certificate -c "$CERT_NAME" "$KEYCHAIN" 2>/dev/null || true

echo "→ Importing cert + private key into login keychain"
# -T flags grant codesign and security access to the private key
# without requiring per-tool prompts. -t agg = aggregate (cert+key).
security import "$TMP/cert.p12" \
  -k "$KEYCHAIN" \
  -P dial \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/xcodebuild \
  -t agg \
  -f pkcs12 >/dev/null

echo ""
echo "→ Verifying via codesign smoke test"
echo "test" > "$TMP/smoketest"
if codesign --sign "$CERT_NAME" "$TMP/smoketest" 2>/dev/null; then
  echo "✓ Cert installed and codesign-capable."
  echo ""
  echo "  Identity:    $CERT_NAME"
  echo "  Valid until: $(date -v+${DAYS}d '+%Y-%m-%d')"
  echo ""
  echo "  Note: 'security find-identity -v -p codesigning' will hide this"
  echo "  cert because it's self-signed (untrusted by Gatekeeper). That's"
  echo "  cosmetic — codesign + xcodebuild still use it normally. Project.yml"
  echo "  references it by CODE_SIGN_IDENTITY = '$CERT_NAME'."
  echo ""
  echo "  Next: ./scripts/install.sh"
else
  echo "✗ Codesign smoke test failed. Run:"
  echo "    security find-identity '$KEYCHAIN'"
  echo "  to debug — should show '$CERT_NAME' even with CSSMERR_TP_NOT_TRUSTED."
  exit 1
fi
