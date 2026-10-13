#!/bin/zsh
# New Password tap: put a fresh Safari-style password (xxxxxx-xxxxxx-xxxxxx) on the Mac's clipboard, marked concealed
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"

# pick <tr set> <count>: that many characters drawn uniformly from the set. tr drops every byte outside
# the set instead of folding it in with a modulo, so no character is likelier than another.
# (tr's only complaint is the pipe head closes once it has enough.)
pick() { tr -dc "$1" < /dev/urandom 2>/dev/null | head -c $2 }

# post <json>: changes how the button looks; the answer does not matter, the password is already in place.
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  curl -q -s -o /dev/null -m 3 "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$1"
}

# ---- the password: 18 lowercase letters, then one of them becomes a capital and another a number ----
# No I or O among the capitals and no 0 or 1 among the digits, so it can be read off and typed by hand.
pw=$(pick 'a-z' 18)
upper=$(pick 'A-HJ-NP-Z' 1)
num=$(pick '2-9' 1)
p=$(pick 'a-r' 1)                          # a letter a…r is a position 1…18
q=$(pick 'a-q' 1)                          # a…q: one of the 17 positions left
[[ ${#pw} == 18 && $upper == [A-Z] && $num == [2-9] && $p == [a-r] && $q == [a-q] ]] ||
  { print -u2 -- "new-password: no randomness from /dev/urandom"; exit 1 }
p=$(( #p - 96 ))
q=$(( #q - 96 ))
(( q >= p )) && (( q++ ))
pw[p]=$upper
pw[q]=$num
pw="${pw[1,6]}-${pw[7,12]}-${pw[13,18]}"

# ---- onto the clipboard ----
# The password reaches osascript through a pipe from a shell builtin: never in an argument, the environment
# or a file. The empty org.nspasteboard.ConcealedType entry asks clipboard managers not to keep or show it.
result=$(print -rn -- "$pw" | osascript -l JavaScript -e '
ObjC.import("AppKit");
function run() {
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  const text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
  if (text.isNil() || text.length === 0) return "empty";
  const item = $.NSPasteboardItem.alloc.init;
  if (!item.setStringForType(text, "public.utf8-plain-text")) return "unwritable";
  if (!item.setDataForType($.NSData.data, "org.nspasteboard.ConcealedType")) return "unwritable";
  const board = $.NSPasteboard.generalPasteboard;
  board.clearContents;
  return board.writeObjects($([item])) ? "ok" : "unwritable";
}')
unset pw
[[ $result == ok ]] || { print -u2 -- "new-password: the clipboard refused the password (${result:-osascript failed})"; exit 1 }

# ---- a moment of ✓ on the button, then its own face again ----
post "{\"cellId\":\"$cell\",\"icon\":\"checkmark\"}"
sleep 1.5
post "{\"cellId\":\"$cell\",\"reset\":true}"
exit 0
