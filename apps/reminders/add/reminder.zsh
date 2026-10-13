# Reminders › From Clipboard and Read Later, their shared part: $reminder_js, a JavaScript for Automation program that
# adds one reminder through EventKit — the stock osascript is all it needs — and reminder_refusal, which words its
# refusals. It talks to EventKit, not to the Reminders app: nothing is launched, and the new reminder reaches Reminders
# (and the user's other devices, through iCloud) as any reminder added by another app does. Functions and data only; a
# script after this one runs it (app.json):
#   "@file:add/reminder.zsh\n@file:add/clipboard.zsh"    — From Clipboard
#   "@file:add/reminder.zsh\n@file:add/read-later.zsh"   — Read Later
#
# Modes (the arguments; data never goes into the program text):
#   clipboard           → the text on the Mac's clipboard: its first line (up to 200 characters) is the title, the rest
#                         the notes; a first line longer than that puts the whole text in the notes, so nothing is lost.
#                         A text that is one web address also becomes the reminder's link.
#   page <url> <title>  → a reminder named after the page, with the address as its link and in its notes.
# The reminder goes to the default list (Reminders › Settings › Default list), with no date. The first time, macOS asks
# whether the agent may have full access to your reminders (EventKit has no add-only access for reminders); the tap
# waits up to 45 s for the answer. It prints "ok", or "!<why not>": !concealed !empty !notext !blank !badlink
# !unanswered !denied !nolist !readonly !save <code> !error <what>.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
read -r -d '' reminder_js <<'JS'
ObjC.import("Foundation");
ObjC.import("AppKit");
ObjC.import("EventKit");

const REMINDER = 1;                                   // EKEntityTypeReminder
const NOT_DETERMINED = 0, FULL_ACCESS = 3;            // EKAuthorizationStatus
function access() { return Number($.EKEventStore.authorizationStatusForEntityType(REMINDER)); }

// One line of text: control and invisible characters and line breaks become spaces, runs of white space one space.
function oneLine(s) {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u2064\ufeff]+/g, " ").replace(/\s+/g, " ").trim();
}
// Notes: line breaks and tabs stay; other control characters go; blank lines around the text go.
function tidy(s) {
  return s.replace(/[\u0000-\u0008\u000b-\u001f\u007f]+/g, "").replace(/^(\s*\n)+/, "").replace(/\s+$/, "");
}
// At most n characters (whole characters: an emoji is never split), with … when cut.
function cut(s, n) {
  const chars = Array.from(s);
  return chars.length <= n ? s : chars.slice(0, n - 1).join("") + "\u2026";
}
const WEB = /^https?:\/\/[^\s"'<>\\^`{|}]+$/i;

function fromClipboard() {
  // What a password manager (or the New Password button) copies is marked so; it never becomes a reminder, which
  // iCloud would carry to every device. The last three are older spellings of the same marks (1Password before 8).
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

// The copied text as a reminder: its first line that is not blank is the title.
function fromText(text) {
  const all = text.replace(/\r\n?/g, "\n");
  const lines = all.split("\n");
  const first = lines.findIndex((line) => oneLine(line) !== "");
  if (first < 0) return "!blank";
  const whole = oneLine(lines[first]);
  const title = cut(whole, 200);
  const notes = cut(tidy(title === whole ? lines.slice(first + 1).join("\n") : lines.slice(first).join("\n")), 20000);
  const trimmed = all.trim();
  const link = (WEB.test(trimmed) && trimmed.length <= 4096) ? trimmed : "";
  return { title: title, notes: notes, link: link };
}

function fromPage(url, name) {
  url = String(url || "").trim();
  if (!WEB.test(url) || url.length > 4096) return "!badlink";
  return { title: cut(oneLine(String(name || "")), 200) || cut(url, 200), notes: url, link: url };
}

function run(argv) {
  try {
    const entry = argv[0] === "clipboard" ? fromClipboard() : argv[0] === "page" ? fromPage(argv[1], argv[2]) : "!error mode";
    if (typeof entry === "string") return entry;

    // Asked only when macOS has never been answered; the answer is waited for, polling (up to 45 s of the tap's 60).
    if (access() === NOT_DETERMINED) {
      const asker = $.EKEventStore.alloc.init;
      const answered = function (granted, error) {};
      try { asker.requestFullAccessToRemindersWithCompletion(answered); }
      catch (e) { asker.requestAccessToEntityTypeCompletion(REMINDER, answered); }
      for (let t = 0; t < 90 && access() === NOT_DETERMINED; t++) delay(0.5);
    }
    const status = access();
    if (status !== FULL_ACCESS) return status === NOT_DETERMINED ? "!unanswered" : "!denied";

    const store = $.EKEventStore.alloc.init;
    const list = store.defaultCalendarForNewReminders;
    if (list.isNil()) return "!nolist";
    if (!list.allowsContentModifications) return "!readonly";
    const reminder = $.EKReminder.reminderWithEventStore(store);
    reminder.setCalendar(list);
    reminder.setTitle(entry.title);
    if (entry.notes) reminder.setNotes(entry.notes);
    if (entry.link) {
      const url = $.NSURL.URLWithString(entry.link);
      if (!url.isNil()) reminder.setURL(url);
    }
    // The NSError comes back in $(): reading a Ref() after an error crashes osascript (EXC_BAD_ACCESS, macOS 26).
    const error = $();
    if (!store.saveReminderCommitError(reminder, true, error)) return "!save " + (error.isNil() ? "?" : error.code);
    return "ok";
  } catch (e) {
    return "!error " + e;
  }
}
JS

# Prints why the reminder was not added, for the answer $1 of $reminder_js, as one line on stderr.
reminder_refusal() {
  case $1 in
    '!concealed')  print -u2 -- "Reminders: the clipboard holds a password; it is not added" ;;
    '!empty')      print -u2 -- "Reminders: the clipboard is empty" ;;
    '!notext')     print -u2 -- "Reminders: there is no text on the clipboard" ;;
    '!blank')      print -u2 -- "Reminders: the clipboard holds only spaces" ;;
    '!badlink')    print -u2 -- "Reminders: only a web page (http or https) can be saved" ;;
    '!unanswered') print -u2 -- "Reminders: macOS is still asking whether the agent may use Reminders" ;;
    '!denied')     print -u2 -- "Reminders: allow the agent in System Settings → Privacy & Security → Reminders" ;;
    '!nolist')     print -u2 -- "Reminders: there is no default list — choose one in Reminders › Settings" ;;
    '!readonly')   print -u2 -- "Reminders: the default list can't take new reminders — choose another in Reminders › Settings" ;;
    '!save '*)     print -ru2 -- "Reminders: the reminder was not saved (EventKit error ${1#!save })" ;;
    *)             print -ru2 -- "Reminders: the reminder was not added: ${1#!}" ;;
  esac
}
