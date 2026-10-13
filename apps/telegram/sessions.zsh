# Telegram › Settings (long press): Active Sessions — every device signed in to the account, where Telegram can also end
# the ones you do not know (it asks first) — through a tg:// link, handed to Telegram by Launch Services as a link
# clicked in a browser is. Telegram runs it whatever the app in front and the keyboard layout, comes to the front and
# opens the screen; nothing is typed, so no permission is needed. It never launches Telegram: `open` would, so the
# script checks first.
# Checked in Telegram 12.10 (Info.plist registers tg: and telegram:; the binary still has the settings sections
# "devices" and "folders") against TelegramSwift 11.15, the latest published source: AppDelegate.processURL activates
# the app and de-miniaturizes its window, then InAppLinks routes tg://settings/devices to RecentSessionsController.
# The button's long press is this file (app.json): "@file:sessions.zsh".
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not by process name: Telegram Desktop (another app, com.tdesktop.Telegram) is a "Telegram" process too.
# lsappinfo asks this login session's Launch Services — the one `open` hands the link to — and prints nothing for an
# app that is not running.
[[ -n $(lsappinfo info -only pid -app ru.keepcoder.Telegram 2>/dev/null) ]] || { print -u2 -- "Telegram is not running"; exit 1 }

# -b: to Telegram itself, not to whatever else claimed tg:// links (Telegram Desktop does).
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b ru.keepcoder.Telegram 'tg://settings/devices' || { print -u2 -- "Telegram did not take the link"; exit 1 }
exit 0
