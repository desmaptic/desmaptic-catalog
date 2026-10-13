# Discord › Direct Messages (tap): Discord's home — direct messages and the friends list — through a discord:// link,
# handed to Discord by Launch Services as a link clicked in a browser is. Discord runs it whatever the app in front and
# the keyboard layout, brings its window to the front, and nothing is typed, so no permission is needed. It never
# launches Discord: `open` would, so the script checks first.
# Checked in Discord 0.0.410 (Info.plist registers discord:; core.asar's handleOpenUrl takes the link's path — for
# discord://-/channels/@me that is /channels/@me — shows and focuses the main window and hands the path to the web
# client, which, build 621195, navigates to it: /channels/@me is its Direct Messages home).
# The button's command is this file (app.json): "@file:home.zsh".
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Discord Launch Services hands the link to.
# The helpers are "Discord Helper (…)": -x matches the app itself only.
pgrep -xqU $UID Discord || { print -u2 -- "Discord is not running"; exit 1 }

# -b: to Discord itself, not to whatever else may have claimed discord:// links (Discord PTB or Canary).
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.hnc.Discord 'discord://-/channels/@me' || { print -u2 -- "Discord did not take the link"; exit 1 }
exit 0
