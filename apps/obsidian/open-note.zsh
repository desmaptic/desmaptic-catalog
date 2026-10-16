# Obsidian › Open Note (tap): one note in one vault (a dashboard, an inbox, a project), named in the button's own first
# line, `vault='' note=''`, which the user fills in (app.json: the line, then "@file:open-note.zsh"): the vault's name
# (its folder's name) and the note's path in it, without .md — or only its name, as a [[link]] finds it. Until both are
# set, the button says what to set. An obsidian://open link, handed to Obsidian through Launch Services as a link clicked
# in a browser is: `open` starts Obsidian when it is closed and brings it to the front, nothing is typed and no permission
# is needed. Obsidian itself says when it has no such vault (a dialog) or note (a notice in its window).
# Checked in Obsidian 1.11.7 and 1.14.4 (the "open" route takes `vault`, the vault's name, and `file`, resolved as a
# link: the note opens in the current tab, as a clicked [[link]] does).
# Both values are percent-encoded byte by byte (in the C locale, so a UTF-8 name keeps its bytes): only letters, digits
# and . _ ~ - stay as they are, so nothing in them can add another parameter to the link.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

vault=${${vault##[[:space:]]#}%%[[:space:]]#}
note=${${${note##[[:space:]]#}%%[[:space:]]#}%.md}
[[ -n $vault && -n $note ]] ||
  { print -u2 -- "Open Note: write the vault’s name and the note’s path in this button’s settings"; exit 1 }

enc() { print -rn -- ${1//(#m)[^A-Za-z0-9._~-]/%${(l:2::0:)$(([##16]#MATCH))}} }

# -b: to Obsidian itself, not to whatever else may have claimed obsidian:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b md.obsidian "obsidian://open?vault=$(enc $vault)&file=$(enc $note)" ||
  { print -u2 -- "Obsidian did not take the link"; exit 1 }
exit 0
