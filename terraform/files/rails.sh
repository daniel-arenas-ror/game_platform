#!/bin/bash
# Usage: /opt/game_platform/bin/rails <command>   e.g. `bin/rails console`, `bin/rails db:seed`
set -euo pipefail
cd /opt/game_platform
TTY_FLAG=""
[ -t 0 ] || TTY_FLAG="-T"
exec docker compose exec $TTY_FLAG web ./bin/rails "$@"
