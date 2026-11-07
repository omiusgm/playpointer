#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

swift build -c release

APP="${PLAYPOINTER_DIST_DIR:-dist}/$APP_NAME.app"
make_bundle .build/release/$EXECUTABLE_NAME "$APP" "0"

IDENTITY="${CODESIGN_IDENTITY:--}"
sign_app "$APP" "$IDENTITY"
echo "Built $APP $VERSION (signed with: $IDENTITY)"
