# Discord › Open Channel (tap): one channel, thread or DM, given by the link Discord copies — through a discord://
# link, handed to Discord by Launch Services as a link clicked in a browser is. Discord runs it whatever the app in
# front and the keyboard layout, brings its window to the front, and nothing is typed, so no permission is needed. It
# never launches Discord: `open` would, so the script checks first.
# The link is the button's own first line, `link=''`, which the user fills in (app.json: the line, then
# "@file:channel.zsh"): Copy Link on a channel, or Copy Message Link on a message — in a DM too — whose channel opens,
# not the message. Until it is set, the button says what to set.
# Checked in Discord 0.0.413 (Info.plist registers discord:; core.asar's handleOpenUrl takes the path of a discord:
# link, hands it to the web client as MAIN_WINDOW_PATH — kept until the window has loaded — and shows the window), as
# home.zsh does for /channels/@me.
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
setopt extended_glob

route=${${link##[[:space:]]#}%%[[:space:]]#}
[[ -n $route ]] || { print -u2 -- "Open Channel: paste a channel's link (Copy Link in Discord) in the first line of the button's script"; exit 1 }
# https://discord.com/channels/<server or @me>/<channel>[/<message>], from Discord, its PTB or Canary; only the digits
# Discord writes, so the value adds nothing else to the link.
route=${route#(#i)(https://|http://|)((ptb|canary).)#discord(app)#.com/}
[[ $route == channels/(@me|<->)/<->(/<->|) ]] ||
  { print -u2 -- "Open Channel: not a Discord channel link: ${link[1,60]}"; exit 1 }
[[ $route == channels/*/*/* ]] && route=${route%/*}

# pgrep sees every account's processes; -U keeps it to this one, whose Discord Launch Services hands the link to.
# The helpers are "Discord Helper (…)": -x matches the app itself only.
pgrep -xqU $UID Discord || { print -u2 -- "Discord is not running"; exit 1 }

# -b: to Discord itself, not to whatever else may have claimed discord:// links (Discord PTB or Canary).
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.hnc.Discord "discord://-/$route" || { print -u2 -- "Discord did not take the link"; exit 1 }
exit 0
