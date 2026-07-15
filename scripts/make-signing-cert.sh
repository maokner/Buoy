#!/bin/bash

# Creates the stable self-signed "Buoy Self-Signed" code-signing identity that
# both local builds (install-local.sh) and release DMGs use. macOS keys Screen
# Recording and Accessibility grants to an app's signing identity, so signing
# every build with this one cert keeps those grants attached across updates.
#
# Run this once per machine. If you already have the identity, this is a no-op.
# The private key never leaves your keychain; do not commit it.

set -euo pipefail

IDENTITY="Buoy Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "'$IDENTITY' already exists in your keychain. Nothing to do."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

cat > cert.conf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Buoy Self-Signed
O = Buoy
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout key.pem -out cert.pem -config cert.conf

# macOS `security` cannot verify OpenSSL 3's default PKCS#12 MAC, so request the
# legacy encryption when the installed OpenSSL supports the flag.
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem \
        -out bundle.p12 -name "$IDENTITY" -passout pass:buoy
else
    openssl pkcs12 -export -inkey key.pem -in cert.pem \
        -out bundle.p12 -name "$IDENTITY" -passout pass:buoy
fi

security import bundle.p12 -k "$KEYCHAIN" -P buoy -T /usr/bin/codesign -A

echo "Created '$IDENTITY'. You can now run ./scripts/install-local.sh"
echo "Back up the identity from Keychain Access if you want to sign releases from another Mac."
