#!/bin/zsh
# Note tap: the text typed on the phone ($DESMAPTIC_INPUT) becomes a new note in Notes, in the default folder of the
# default account (Notes › Settings › Default account): every line a paragraph, the first one the title when it is at most
# 200 characters long, a line that is one web address a link. Notes has no framework another program can write notes
# through (Reminders has EventKit): the note is made by Notes itself, through its AppleScript dictionary (`make` of the
# Cocoa standard suite, the application's `default account`, the account's `default folder`, the note's `body` — its
# HTML). So the first tap brings up the macOS question whether the agent may control Notes, and a tap while Notes is
# closed starts it. Only `body` is set: Notes names a note after its first line, set here in Notes' Title style (<h1>).
# The text travels in the environment of the first osascript (DESMAPTIC_INPUT) and on the standard input of the second
# (the note's HTML), both read by Foundation as UTF-8 — never in their arguments, which any app of this user can read,
# nor in the program texts. The second runs with an empty environment: a Notes it starts gets the account's own.
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
  print -ru2 -- "Note: $2"
  exit 1
}

[[ -n ${DESMAPTIC_INPUT//[[:space:]]/} ]] || fail other "Nothing to note: the text is empty"

# The text as the note's HTML: every line a paragraph (<div>, an empty one <div><br></div>, as Notes writes them), & < > "
# escaped, so nothing typed can become markup. Prints "ok", a line break and the HTML, or "!<why not>": !blank !error.
read -r -d '' note_js <<'JS'
ObjC.import("Foundation");

// One line of text: control and invisible characters and line breaks become spaces, runs of white space one space.
function oneLine(s) {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u2064\ufeff]+/g, " ").replace(/\s+/g, " ").trim();
}
function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
// A paragraph's text, escaped, its spaces kept: HTML folds a run of spaces into one, so all but the last space of a run
// (and a space that starts the line) become no-break spaces; a tab counts as four spaces.
function paragraph(s) {
  return esc(s.replace(/\t/g, "    ")).replace(/ (?= )/g, "&nbsp;").replace(/^ /, "&nbsp;");
}
function link(url) { return "<a href=\"" + esc(url) + "\">" + esc(url) + "</a>"; }
const WEB = /^https?:\/\/[^\s"'<>\\^`{|}]+$/i;

function run() {
  try {
    const value = $.NSProcessInfo.processInfo.environment.objectForKey("DESMAPTIC_INPUT");
    const lines = (value.isNil() ? "" : value.js).replace(/\r\n?|[\u0085\u2028\u2029]/g, "\n")
      .replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "").split("\n").map((line) => line.replace(/[ \t]+$/, ""));
    const first = lines.findIndex((line) => oneLine(line) !== "");
    if (first < 0) return "!blank";
    let last = lines.length - 1;
    while (oneLine(lines[last]) === "") last--;
    return "ok\n" + lines.slice(first, last + 1).map((line, i) => {
      const trimmed = line.trim();
      if (trimmed === "") return "<div><br></div>";
      if (WEB.test(trimmed) && trimmed.length <= 4096) return "<div>" + link(trimmed) + "</div>";
      if (i == 0 && Array.from(trimmed).length <= 200) return "<div><h1>" + esc(trimmed) + "</h1></div>";
      return "<div>" + paragraph(line) + "</div>";
    }).join("");
  } catch (e) {
    return "!error " + e;
  }
}
JS

# The HTML, from the standard input (read through Foundation as UTF-8), becomes a new note in the default folder of the
# default account. Nothing of the note is read back. Prints "ok" or "!notes <number>".
read -r -d '' note_osa <<'OSA'
use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

on run argv
	set noteData to current application's NSFileHandle's fileHandleWithStandardInput()'s readDataToEndOfFile()
	set noteHTML to current application's NSString's alloc()'s initWithData:noteData encoding:(current application's NSUTF8StringEncoding)
	if noteHTML is missing value or (noteHTML's |length|()) = 0 then return "!error no text reached the script"
	set noteHTML to noteHTML as text
	try
		with timeout of 30 seconds
			tell application id "com.apple.Notes"
				set targetFolder to default folder of default account
				make new note at targetFolder with properties {body:noteHTML}
			end tell
		end timeout
	on error number errorNumber
		return "!notes " & errorNumber
	end try
	return "ok"
end run
OSA

answer=$(osascript -l JavaScript -e "$note_js" 2>&1)
case $answer in
  ok$'\n'*) ;;
  '!blank') fail other "Nothing to note: the text is only spaces" ;;
  *)        fail other "The note was not made: ${answer#!}" ;;
esac

# env -i: a closed Notes, started by the AppleScript, gets the account's own environment, not the agent's token.
# The HTML goes in through a pipe from a shell builtin.
answer=$(print -rn -- "${answer#ok$'\n'}" | env -i /usr/bin/osascript -e "$note_osa" 2>&1)
case $answer in
  ok) ;;
  '!notes -1743') fail permission "The agent may not control Notes: allow it in System Settings → Privacy & Security → Automation" ;;
  '!notes -1712') fail timeout "Notes did not answer in time: check Notes before trying again" ;;
  '!notes -1728') fail config "Notes has no default folder to add the note to: choose a default account in Notes › Settings" ;;
  '!notes '*)     fail other "Notes did not add the note (error ${answer#!notes })" ;;
  *)              fail other "The note was not added: ${answer#!}" ;;
esac

# ---- a moment of ✓ on the button, then its own face again ----
call update-button "{\"cellId\":\"$cell\",\"icon\":\"checkmark\"}" >/dev/null
sleep 1.5
call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
exit 0
