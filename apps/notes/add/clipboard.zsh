# Notes › From Clipboard, the tap: the text on the Mac's clipboard becomes a new note in the default folder ($note_js
# clipboard, then add_note — add/note.zsh). The copied text never passes through the command line: osascript reads the
# clipboard itself (pbpaste would read it in the C locale and mangle every letter outside ASCII), and the note's HTML
# reaches the second osascript on its standard input. Nothing is typed, Notes is not brought forward, and the clipboard is
# left as it was. Silent when it worked; otherwise one line on stderr and the phone shakes the button. The command is
# (app.json):
#   "@file:add/note.zsh\n@file:add/clipboard.zsh"
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

answer=$(/usr/bin/osascript -l JavaScript -e "$note_js" clipboard 2>&1)
if [[ $answer != ok$'\n'* ]]; then
  note_refusal "$answer"
  exit 1
fi
add_note "${answer#ok$'\n'}" || exit 1
exit 0
