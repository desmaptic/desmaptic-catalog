# Mail › Unread, the tap: brings Mail to the front, as a click on its Dock icon does, from any page the button is on.
# It never launches Mail: at launch Mail fetches mail and sends what waits in the Outbox, and a tap sends nothing.
# No permission needed: `open -b` hands the running app to Launch Services. The command is this file (app.json).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Mail Launch Services brings forward.
pgrep -xqU $UID Mail || { print -u2 -- "Mail is not running"; exit 1 }
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.apple.mail || { print -u2 -- "Mail did not come to the front"; exit 1 }
exit 0
