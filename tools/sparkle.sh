#!/bin/bash -l
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Steps:
# Download a fresh new unsigned generate_appcast on the machine.
# Unlock th edefault keychain
# Find the certificate name based on its team id.
# codesign it on the server (where the certificate is).
# Add generic password with -T set to the path of the new codesigned generate_appcast.
# Set generic-password-partition-list with the teamid of the used certificate.
# Execute the new codesigned and authorized generate_appcast on the folder with an binary to release.
# Remove key from keychain.
# Remove local generate_appcast.

# Variables/Parameters
KEYCHAIN_PASSWORD=$1
APPCAST_PASSWORD=$2
APPCAST_BASE_URI=$3
SPARKLE_VERSION=$4
TEAM_ID=$5

echo "---- Clean Cache ----"

rm -rf "/Users/smf/Library/Caches/Sparkle_generate_appcast/"

echo "---- Download latest generate_appcast release ----"

curl -L https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.bz2 --output sparkle.tar.bz2

mkdir sparkle_dl
tar xjf sparkle.tar.bz2 -C sparkle_dl
# Only retain the generate_appcast binary.
mv sparkle_dl/bin/generate_appcast .
# Remove downloaded files.
rm -rf sparkle_dl sparkle.tar.bz2

echo "---- codesign generate_appcast ----"

echo "Default Keychain:"
security default-keychain

echo "Unlock login keychain"
security unlock-keychain -p $KEYCHAIN_PASSWORD "/Users/smf/Library/Keychains/login.keychain-db"

# Get certificate identity from the keychain using the given team id.
CERTIFICATE_NAME=`security find-certificate -c $TEAM_ID | grep -e "alis" | sed 's/    "alis"<blob>="//g' | sed 's/"//g'`
echo "Signing Identity: '$CERTIFICATE_NAME'"

codesign -s "$CERTIFICATE_NAME" ./generate_appcast
codesign -dv ./generate_appcast

echo "----- Add Private Key ----"

# If any, delete pre-existing private keys from the keychain.
echo "Delete credential in login keychain"
security delete-generic-password -a "ed25519" -s "https://sparkle-project.org" -D "private key" "/Users/smf/Library/Keychains/login.keychain-db"
# Add the (new) private key to the keychain.
# Used parameters: account, service, description/type, allowed application, password, related keychain.
echo "Add credential in login keychain"
security add-generic-password    -a "ed25519" -s "https://sparkle-project.org" -D "private key" -T ./generate_appcast -w $APPCAST_PASSWORD "/Users/smf/Library/Keychains/login.keychain-db"
# Using the team id, authorise the identity codesigning the generate_appcast to access the private key.
security set-generic-password-partition-list -a "ed25519" -s "https://sparkle-project.org" -k $KEYCHAIN_PASSWORD -S teamid:$TEAM_ID "/Users/smf/Library/Keychains/login.keychain-db"

# Use generate_appcast to access the private key within the default keychain.
# The default keychain must be the one used previously.
echo "** generate_appcast **"

./generate_appcast $APPCAST_BASE_URI

echo "---- clean up ----"
# Delete the private key and codesigned version of the generate_appcast.
security delete-generic-password -a "ed25519" -s "https://sparkle-project.org" -D "private key"
rm generate_appcast
