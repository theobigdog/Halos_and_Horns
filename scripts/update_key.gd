# The public half of the key that release builds are signed with. The updater
# only installs a download whose signature checks out against this.
#
# Made by tools/make_update_key.sh. The private half is the UPDATE_SIGNING_KEY
# secret on GitHub, never this repository. While this is empty, the game
# can't check anything, so it only points players at the download page.
extends RefCounted

const PEM := ""
