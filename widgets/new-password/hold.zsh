#!/bin/zsh
# New Password hold: empty the Mac's clipboard, so a password copied a moment ago does not linger there
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"

# post <json>: changes how the button looks; the answer does not matter, the clipboard is already empty.
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  curl -q -s -o /dev/null -m 3 "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$1"
}

# clearContents removes every item. It only writes: nothing on the clipboard is read, so macOS does not
# ask about pasteboard access. An already empty clipboard also gets the ✓ — it is what the user wanted.
result=$(osascript -l JavaScript -e '
ObjC.import("AppKit");
function run() {
  $.NSPasteboard.generalPasteboard.clearContents;
  return "ok";
}')
[[ $result == ok ]] || { print -u2 -- "new-password: could not clear the clipboard (${result:-osascript failed})"; exit 1 }

# ---- a moment of ✓ on the button, then its own face again ----
post "{\"cellId\":\"$cell\",\"icon\":\"checkmark\"}"
sleep 1.5
post "{\"cellId\":\"$cell\",\"reset\":true}"
exit 0
