# Claude › a new Claude Code session in the user's project folder: claude://code/new?folder=<path>, handed to Claude
# through Launch Services as a link clicked in a browser is, so it works with Claude in the background and starts Claude
# when it is closed. Checked in Claude 2.31226.1 (com.anthropic.claudefordesktop) by reading only: Info.plist registers
# claude:, and the app's link handler takes code/new with any number of folder= (URLSearchParams, so "+" is a space
# there) and opens Claude Code's start screen with those folders, nothing sent until the user types; a folder inside
# <repo>/.claude/worktrees/ is taken as the repository itself. The folder is the button's setting, on the line before
# this file: `folder="~/Developer/my-app"` — a full path or one under ~ (expanded here: Claude gets the link, not a
# shell). While it is empty the button refuses and says where to set it. Only a folder that exists goes into the link.
# The button's command is that line, then this file (app.json):
#   "folder=\"\"   # ← …\n@file:code-folder.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ -n $folder ]] ||
  { print -u2 -- "Session in Folder: set your project folder in this button’s settings, e.g. folder=\"~/Developer/my-app\""; exit 1 }
case $folder in
  '~')  folder=$HOME ;;
  '~/'*) folder=$HOME/${folder#'~/'} ;;
esac
[[ $folder == /* ]] || { print -ru2 -- "Not a full path: $folder (start it with / or ~/)"; exit 1 }
[[ -d $folder ]] || { print -ru2 -- "No such folder: $folder"; exit 1 }
folder=${folder:a}                              # absolute, without . and .., no trailing /

# Every byte but these is %XX. LC_ALL=C: one byte at a time, a name in any script included.
encoded=
for (( k = 1; k <= ${#folder}; k++ )); do
  c=${folder[k]}
  if [[ $c == [A-Za-z0-9/._-] ]]; then
    encoded+=$c
  else
    printf -v hex '%%%02X' "'$c"
    encoded+=$hex
  fi
done

# -b: to Claude itself, not to whatever else may have claimed claude:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.anthropic.claudefordesktop "claude://code/new?folder=$encoded" ||
  { print -u2 -- "Claude did not take the link"; exit 1 }
exit 0
