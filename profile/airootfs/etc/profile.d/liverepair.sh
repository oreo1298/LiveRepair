# shellcheck shell=sh
# Start the LiveRepair desktop when the live user is logged in on tty1.
if [ "$(id -un)" = "live" ] && [ -z "${DISPLAY-}" ] && [ "${XDG_VTNR-}" = 1 ]; then
    /usr/local/bin/liverepair-session
fi
