# Proxyman › macOS Proxy, the tap: brings Proxyman to the front, as a click on its Dock icon does, from any page the
# button is on. It never launches Proxyman: at launch Proxyman overrides the Mac's proxy settings by default ("Auto
# Override System Proxy Settings at Launch", Proxyman 6.6.0), and a tap must not change them.
# No permission needed: `open -b` hands the running app to Launch Services. The command is this file (app.json).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Proxyman Launch Services brings forward.
pgrep -xqU $UID Proxyman || { print -u2 -- "Proxyman is not running"; exit 1 }
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.proxyman.NSProxy || { print -u2 -- "Proxyman did not come to the front"; exit 1 }
exit 0
