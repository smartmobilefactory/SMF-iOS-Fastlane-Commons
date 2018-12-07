#!/bin/bash
#
# Uploads the base language strings to phrase app and downloads the translated strings.
#
# Author Hans Seiffert
#
# Last revised 19/01/2017

# The script should fail as soon as one of the called commands fail
set -e 
set -o pipefail

export phraseappAccessToken="$stratoPhraseappAccessToken"
export phraseappFilesPrefix=""
export phraseappProjectId="25ff19777583107ec9982c2c308c6da0"
export phraseappSource="en"
export phraseappLocales="de es fr nl pt tr en"
export phraseappFormat="strings"
export phraseappForceupdate=0
export phraseappGitBranch="$1"
export phraseappForbidCommentsInSource=0

#
# App targets
#

export phraseappBasedir='../Resources/HiDrive'
export phraseappFiles='en.lproj/Localizable.strings en.lproj/InfoPlist.strings'

/Users/smf/PhraseApp/push.sh
/Users/smf/PhraseApp/pull.sh

#
# UploadExtension HiDrive
#

export phraseappProjectId="44af9b5d1d4a30b6622d5afe28d19ba7"
export phraseappBasedir='../Extensions/UploadExtension/Resources/HiDrive'
export phraseappFiles="en.lproj/InfoPlist.strings"

/Users/smf/PhraseApp/push.sh
/Users/smf/PhraseApp/pull.sh

#
# DocumentProvider Extension HiDrive
#

export phraseappProjectId="909b107b6a3d162914e2a88096c3069f"
export phraseappBasedir='../Extensions/HiDrive-DocumentProviderExtension'
export phraseappFiles="en.lproj/InfoPlist.strings"

/Users/smf/PhraseApp/push.sh
/Users/smf/PhraseApp/pull.sh
