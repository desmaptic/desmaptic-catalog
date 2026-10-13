# Notes › From Clipboard and Read Later, their shared part: $note_js, a JavaScript for Automation program that turns the
# copied text or a web page into the note's HTML; $note_osa, an AppleScript that hands that HTML to Notes as a new note;
# add_note, which runs it; and note_refusal, which words the refusals. Functions and data only; a script after this one
# runs them (app.json):
#   "@file:add/note.zsh\n@file:add/clipboard.zsh"    — From Clipboard
#   "@file:add/note.zsh\n@file:add/read-later.zsh"   — Read Later
#
# Notes has no framework another program can write notes through (Reminders has EventKit): a note is made by Notes
# itself, through its AppleScript dictionary (Notes 4.13, Notes.sdef: `make` of the Cocoa standard suite, the
# application's `default account`, the account's `default folder`, the note's `body` — "the HTML content of the note").
# So the first tap brings up the macOS question whether the agent may control Notes, and a tap while Notes is closed
# starts it (whether it then stays behind the app in front has not been seen live yet) — the button's point is to save
# what is on the Mac, and nothing leaves the Mac because Notes starts; the texts say it starts Notes. The note goes to
# the default folder of the default account (Notes › Settings › Default account), not to the folder shown in Notes;
# the user's other devices get it through iCloud when that account syncs.
# Only `body` is set, never `name`: Notes names a note after its first line ("normally the first line of the body",
# says the dictionary), so the title is the body's first line, set in Notes' Title style (<h1>, as Notes' own HTML has it).
#
# The text travels in the environment of the first osascript (DESMAPTIC_PAGE_URL, DESMAPTIC_PAGE_TITLE) and on the
# standard input of the second (the note's HTML), never in their arguments, which any app of this user can read, nor in
# the program texts. The second runs with nothing else: Notes, when it starts it, gets osascript's environment.
#
# $note_js modes (the first argument):
#   clipboard → the text on the Mac's clipboard, as it is: every line a paragraph, blank lines kept, blank lines at the
#               start and the end dropped. The first line is the title when it is at most 200 characters long; a line
#               that is one web address (http or https) becomes a link. A password manager's copy is refused.
#   page      → DESMAPTIC_PAGE_TITLE as the title (the address when there is none), then DESMAPTIC_PAGE_URL as a link.
# It prints "ok", a line break and the HTML, or "!<why not>": !concealed !empty !notext !blank !badlink !toolong
# !error <what>. $note_osa prints "ok", or "!notes <AppleScript error number>".
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
read -r -d '' note_js <<'JS'
ObjC.import("Foundation");
ObjC.import("AppKit");

// One line of text: control and invisible characters and line breaks become spaces, runs of white space one space.
function oneLine(s) {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u2064\ufeff]+/g, " ").replace(/\s+/g, " ").trim();
}
// At most n characters (whole characters: an emoji is never split), with \u2026 when cut.
function cut(s, n) {
  const chars = Array.from(s);
  return chars.length <= n ? s : chars.slice(0, n - 1).join("") + "\u2026";
}
// Text in HTML: & < > " escaped, so nothing copied can become markup.
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
// Size in UTF-8 bytes, counted by hand: a lone surrogate half would make encodeURIComponent throw.
function utf8Bytes(s) {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) n += 1;
    else if (c < 0x800) n += 2;
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length && (s.charCodeAt(i + 1) & 0xfc00) == 0xdc00) { n += 4; i++; }
    else n += 3;
  }
  return n;
}
function environment(name) {
  const value = $.NSProcessInfo.processInfo.environment.objectForKey(name);
  return value.isNil() ? "" : value.js;
}

function fromClipboard() {
  // What a password manager (or the New Password button) copies is marked so; it never becomes a note, which iCloud
  // would carry to every device. The last three are older spellings of the same marks (1Password before 8).
  const board = $.NSPasteboard.generalPasteboard;
  const marks = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
    "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping"];
  const items = ObjC.unwrap(board.pasteboardItems) || [];
  const typeLists = [ObjC.deepUnwrap(board.types) || []].concat(items.map((item) => ObjC.deepUnwrap(item.types) || []));
  if (typeLists.some((types) => types.some((type) => marks.includes(type)))) return "!concealed";

  const copied = board.stringForType("public.utf8-plain-text");
  if (copied.isNil()) return items.length ? "!notext" : "!empty";
  return fromText(copied.js);
}

// The copied text as the note: every line a paragraph (<div>, an empty one <div><br></div>, as Notes writes them).
function fromText(text) {
  const lines = text.replace(/\r\n?|[\u0085\u2028\u2029]/g, "\n").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "")
    .split("\n").map((line) => line.replace(/[ \t]+$/, ""));
  const first = lines.findIndex((line) => oneLine(line) !== "");
  if (first < 0) return "!blank";
  let last = lines.length - 1;
  while (oneLine(lines[last]) === "") last--;
  return lines.slice(first, last + 1).map((line, i) => {
    const trimmed = line.trim();
    if (trimmed === "") return "<div><br></div>";
    if (WEB.test(trimmed) && trimmed.length <= 4096) return "<div>" + link(trimmed) + "</div>";
    if (i == 0 && Array.from(trimmed).length <= 200) return "<div><h1>" + esc(trimmed) + "</h1></div>";
    return "<div>" + paragraph(line) + "</div>";
  }).join("");
}

function fromPage() {
  const url = environment("DESMAPTIC_PAGE_URL").trim();
  if (!WEB.test(url) || url.length > 4096) return "!badlink";
  const title = cut(oneLine(environment("DESMAPTIC_PAGE_TITLE")), 200) || cut(url, 200);
  return "<div><h1>" + esc(title) + "</h1></div><div>" + link(url) + "</div>";
}

function run(argv) {
  try {
    const html = argv[0] === "clipboard" ? fromClipboard() : argv[0] === "page" ? fromPage() : "!error mode";
    if (html.startsWith("!")) return html;
    // One tap's note stays under 800 KB; a longer text is better pasted into a note on the Mac.
    if (utf8Bytes(html) > 800000) return "!toolong";
    return "ok\n" + html;
  } catch (e) {
    return "!error " + e;
  }
}
JS

# The HTML, from the standard input (read through Foundation as UTF-8), becomes a new note in the default folder of the
# default account. Nothing of the note is read back.
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

# Makes the note from the HTML $1. Silent when it worked; otherwise one line on stderr, and a non-zero status.
add_note() {
  local answer
  # env -i: a closed Notes, started by the AppleScript, gets the account's own environment, not the agent's token.
  # The HTML goes in through a pipe from a shell builtin.
  answer=$(print -rn -- "$1" | env -i /usr/bin/osascript -e "$note_osa" 2>&1)
  [[ $answer == ok ]] && return 0
  note_refusal "$answer"
  return 1
}

# Prints why the note was not added, for the answer $1 of $note_js or $note_osa, as one line on stderr.
note_refusal() {
  case $1 in
    '!concealed')   print -u2 -- "Notes: the clipboard holds a password; it is not added" ;;
    '!empty')       print -u2 -- "Notes: the clipboard is empty" ;;
    '!notext')      print -u2 -- "Notes: there is no text on the clipboard" ;;
    '!blank')       print -u2 -- "Notes: the clipboard holds only spaces" ;;
    '!badlink')     print -u2 -- "Notes: only a web page (http or https) can be saved" ;;
    '!toolong')     print -u2 -- "Notes: the text is too long for one tap (over 800 KB) — paste it into a note on the Mac" ;;
    '!notes -1743') print -u2 -- "The agent may not control Notes: allow it in System Settings → Privacy & Security → Automation" ;;
    '!notes -1712') print -u2 -- "Notes did not answer in time — check Notes before trying again" ;;
    '!notes -1728') print -u2 -- "Notes has no default folder to add the note to — choose a default account in Notes › Settings" ;;
    '!notes '*)     print -ru2 -- "Notes did not add the note (error ${1#!notes })" ;;
    *)              print -ru2 -- "Notes: the note was not added: ${1#!}" ;;
  esac
}
