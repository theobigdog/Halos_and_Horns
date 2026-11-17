#!/usr/bin/env bash
# Makes the key that releases are signed with, for the in-game updater.
# Run it once, from anywhere in the repository:
#
#   bash tools/make_update_key.sh [where to keep the private key]
#
# It writes:
#   - the PRIVATE key to a file outside the repository (default
#     ~/halos-and-horns-update-key.pem). That's the one secret: whoever has it
#     can make updates every player's game will install. Keep a copy somewhere
#     safe (a password manager), and never commit it.
#   - the PUBLIC key into scripts/update_key.gd, which is committed: games
#     check downloads against it.
# Then it tells you the one command that gives the private key to the release
# workflow, as the UPDATE_SIGNING_KEY secret, so every release is signed by itself.
#
# Games released with this public key only accept updates signed with this
# private key. Making a new key later is possible, but games already out there
# won't accept the new key's updates: their players would download one
# release by hand. So make it once and keep it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${1:-$HOME/halos-and-horns-update-key.pem}"
KEY="$(cd "$(dirname "$KEY")" && pwd)/$(basename "$KEY")"
OUT="$ROOT/scripts/update_key.gd"

case "$KEY" in
	"$ROOT"/*) echo "Keep the private key outside the repository, not in $ROOT." >&2; exit 1 ;;
esac
if [ -e "$KEY" ]; then
	echo "$KEY already exists. Use it (and don't make a new key), or pick another path." >&2
	exit 1
fi
if grep -q -- "-----BEGIN PUBLIC KEY-----" "$OUT"; then
	echo "scripts/update_key.gd already has a public key. A new one would stop released games" >&2
	echo "from updating. If that's really what you want, empty PEM in that file first." >&2
	exit 1
fi

(umask 077 && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$KEY" 2>/dev/null)
PUBLIC="$(openssl pkey -in "$KEY" -pubout)"

cat > "$OUT" <<EOF
# The public half of the key that release builds are signed with. The updater
# only installs a download whose signature checks out against this.
#
# Made by tools/make_update_key.sh. The private half is the UPDATE_SIGNING_KEY
# secret on GitHub (and wherever its owner keeps a copy), never this repository.
extends RefCounted

const PEM := """$PUBLIC
"""
EOF

echo "Private key: $KEY (keep a copy somewhere safe, never commit it)"
echo "Public key:  scripts/update_key.gd (commit this)"
echo
echo "Now give the private key to the release workflow:"
echo
echo "  gh secret set UPDATE_SIGNING_KEY --repo theobigdog/Halos_and_Horns < \"$KEY\""
echo
echo "(or paste the file's contents under Settings > Secrets and variables > Actions)."
echo "Releases made after that commit is in are signed, and games from that release on update themselves."
