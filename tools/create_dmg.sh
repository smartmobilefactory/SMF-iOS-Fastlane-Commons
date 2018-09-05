#!/bin/bash
#
# Script to create a DMG from build App.
# 
# The script creates a dmg from new app,
# code signes the .dmg file and then uploads it to server
#
# Bartosz Swiatek
# (c) Smart Mobile Factory
#
# 04.09.2018

#set -x

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
export PATH

#
# Setup
#

CREATE_DMG=true
CODE_SIGN=false
CODE_SIGN_ID="JZ2H644EU7"
UPLOAD_TO_HOCKEY=false
HOCKEYAPP_TOKEN=

#
# Variables
#

APPPATH=""

#
# Helper
#

function usage() {
	echo "Script to create a DMG from .app and upload it"
	echo
	echo "Required parameters:"
	echo -e "--appPath, -p\t\t: Path to the .app"
	# should we separate app name from dmg name?
	echo
	echo "Optional"
	echo -e "--codesign, -cs\t\t: Enable code signing of the DMG; default off"
	echo -e "--codesignid, -ci\t: Code signing identity, required if --codesign or -cs was used"
	echo -e "--upload, -u\t\t: Upload the DMG to HockeyApp; HockeyApp Token and HockeyApp AppID need to be configurated; default off"
	echo
	exit 0
}

#
# Main Loop
#

while [ $# -gt 0 ]; do
	case "$1" in
		--appPath | -p)
			# Path where the App is stored after a successful build
			APPPATH="$2"
			shift 2
			;;
		--codesign | -cs)
			CODE_SIGN=true
			shift
			;;
		--codesignid | -ci)
			CODE_SIGN_ID=$2
			shift 2
			;;
		--upload | -u)
			UPLOAD_TO_HOCKEY=true
			shift
			;;
		-*)
			usage
			;;
		*)
	esac
done

if [ -z $APPPATH ]; then
	usage
fi

INFO_PLIST=$APPPATH/Contents/Info.plist
NAME=$(defaults read $INFO_PLIST CFBundleName)
VOLNAME=$NAME
VERSION=$(defaults read $INFO_PLIST CFBundleShortVersionString)
SHORT_VERSION=$(defaults read $INFO_PLIST CFBundleVersion)
APPDIR=$(dirname $APPPATH)
APPVERSION=${VERSION}-${SHORT_VERSION}
APPFULLNAME=${NAME}-${APPVERSION}
SRCFOLDER=${APPDIR}/${APPFULLNAME}

#
# DMG
#

if [ $CREATE_DMG = true ]; then
	mkdir -p ${SRCFOLDER}
	cp -r ${APPPATH} ${SRCFOLDER}
	cd ${SRCFOLDER}
	ln -s /Applications .
	cd ..
	hdiutil create ${NAME}.dmg -volname ${VOLNAME} -srcfolder ${SRCFOLDER}
	if [ $? -gt 0 ]; then
		echo "Abort: Error creating DMG"
		exit 1
	fi
fi

#
# Code Sign
#

if [ $CODE_SIGN = true ]; then
	if [ -z $CODE_SIGN_ID ]; then
		echo "Abort: Code Sign Identity is missing"
		exit 1
	fi
	codesign -s $CODE_SIGN_ID ${APPDIR}/${NAME}.dmg
	if [ $? -gt 0 ]; then
		echo "Abort: Error code signing the DMG"
		exit 1
	fi
fi

# check if signed correctly
# spctl -a -t open --context context:primary-signature -v MyImage.dmg

#
# Upload
#
# HockeyApp create version, then update version will upload dmg
#

HOCKEYAPP_APPID=$(defaults read $INFO_PLIST HockeyAppId)

if [ $UPLOAD_TO_HOCKEY = true ]; then
	if [ -z $HOCKEYAPP_TOKEN ]; then
		echo "Abort: Missing HockeyApp Token"
		exit 1
	fi

	if [ -z $HOCKEYAPP_APPID ]; then
		echo "Abort: Missing HockeyApp AppID"
		exit 1
	fi

	curl \
	-F "bundle_short_version=${VERSION}" \
	-F "bundle_version=${SHORT_VERSION}" \
	-H "X-HockeyAppToken: ${HOCKEYAPP_TOKEN}" \
	https://rink.hockeyapp.net/api/2/apps/${HOCKEYAPP_APPID}/app_versions/${VERSION}-${SHORT_VERSION}
fi


echo "Done."
