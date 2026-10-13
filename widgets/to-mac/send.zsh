#!/bin/zsh
# To the Mac tap: the text typed on the phone ($DESMAPTIC_INPUT) goes onto the Mac's clipboard; a link alone,
# http or https, also opens in the default browser. The text is never drawn on the button and never put in an
# argument or a file: it may be a token or a password.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# fail <kind> <message>: the toast after the tap says why (/api/error), then the tap ends.
fail() {
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "To the Mac: $2"
  exit 1
}

[[ -n ${DESMAPTIC_INPUT//[[:space:]]/} ]] || fail other "Nothing to send: the text is empty"

# The text reaches osascript through a pipe from a shell builtin, as UTF-8; NSPasteboard keeps every script.
# env -i: a browser osascript starts gets its environment; so a closed one gets the account's own, not the agent's token.
result=$(print -rn -- "$DESMAPTIC_INPUT" | env -i /usr/bin/osascript -l JavaScript -e '
ObjC.import("AppKit");
function run() {
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  const text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
  if (text.isNil() || text.length === 0) return "unreadable";
  const board = $.NSPasteboard.generalPasteboard;
  board.clearContents;
  if (!board.setStringForType(text, $.NSPasteboardTypeString)) return "unwritable";
  const link = text.stringByTrimmingCharactersInSet($.NSCharacterSet.whitespaceAndNewlineCharacterSet).js;
  if (!/^https?:\/\/[^\s]+$/i.test(link)) return "copied";
  const url = $.NSURL.URLWithString(link);
  return !url.isNil() && $.NSWorkspace.sharedWorkspace.openURL(url) ? "opened" : "copied, not opened";
}' 2>/dev/null)
case $result in
  copied|opened) ;;
  "copied, not opened") fail other "The text is on the clipboard, but the browser did not open the link" ;;
  *) fail other "The clipboard refused the text (${result:-osascript failed})" ;;
esac

# ---- a moment of ✓ (or the browser's compass) on the button, then its own face again ----
[[ $result == opened ]] && icon=safari || icon=checkmark
call update-button "{\"cellId\":\"$cell\",\"icon\":\"$icon\"}" >/dev/null
sleep 1.5
call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
exit 0
