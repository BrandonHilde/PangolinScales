#!/bin/sh
# Updates this app to the newest version on GitHub: pulls its latest commits, then moves the code it shares with the
# other Pangolin tools (libs/shared) and OdinUI (libs/odinui) to the versions those commits expect. A plain git pull
# leaves the submodules where they were, and the build then fails. build.sh on its own builds whatever is here now,
# so updating is up to you: run this, then ./build.sh.
set -e
cd "$(dirname "$0")"
if ! git pull --ff-only; then
	echo "" >&2
	echo "Could not update: this copy has changes or commits of its own that a plain update would mix in." >&2
	echo "Commit or stash them, or merge by hand, then run ./update.sh again." >&2
	exit 1
fi
git submodule update --init --recursive
echo "Up to date. Run ./build.sh to build it."
