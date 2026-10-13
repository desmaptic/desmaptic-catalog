# Telegram › Open Chat (tap): the chat of one username — a person, a group, a channel or a bot — through a
# tg://resolve link, handed to Telegram by Launch Services as a t.me link clicked in a browser is. Telegram runs it
# whatever the app in front and the keyboard layout, comes to the front and opens the chat; nothing is typed, so no
# permission is needed. It never launches Telegram: `open` would, so the script checks first.
# The username is the button's own first line, `user=''`, which the user fills in (app.json: the line, then
# "@file:chat.zsh"); "@name" and a t.me/name link are taken as well. Until it is set, the button says what to set.
# Checked in Telegram 12.10: Info.plist registers tg: and telegram:, and the binary's tg:// route table has "resolve"
# next to "settings", which sessions.zsh uses; tg://resolve?domain=<username> is the link Telegram documents for
# opening a username.
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
setopt extended_glob

name=${${user##[[:space:]]#}%%[[:space:]]#}
name=${name#@}
name=${name#(#i)(https://|http://)#(www.)#(t.me|telegram.me)/}
[[ -n $name ]] || { print -u2 -- "Open Chat: write a username, without @, in the first line of the button's script"; exit 1 }
# Telegram usernames: Latin letters, digits and underscores, starting with a letter; this also keeps the value from
# adding anything to the link.
[[ $name == [A-Za-z][A-Za-z0-9_]## ]] && (( ${#name} >= 4 && ${#name} <= 32 )) ||
  { print -u2 -- "Open Chat: not a Telegram username: ${name[1,40]}"; exit 1 }

# By bundle id, not by process name: Telegram Desktop (another app, com.tdesktop.Telegram) is a "Telegram" process too.
[[ -n $(lsappinfo info -only pid -app ru.keepcoder.Telegram 2>/dev/null) ]] || { print -u2 -- "Telegram is not running"; exit 1 }

# -b: to Telegram itself, not to whatever else claimed tg:// links (Telegram Desktop does).
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b ru.keepcoder.Telegram "tg://resolve?domain=$name" || { print -u2 -- "Telegram did not take the link"; exit 1 }
exit 0
