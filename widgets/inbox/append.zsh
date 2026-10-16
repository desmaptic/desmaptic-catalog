#!/bin/zsh
# To Inbox tap: the text typed on the phone ($DESMAPTIC_INPUT) becomes a new reminder in the default list of Reminders
# — or, when the button's setting names a file, one task line, "- [ ] 14:05 text", at the end of that Markdown file on
# the Mac: an Obsidian vault's inbox, or a repository's INBOX.md that an AI agent reads when its session starts. The
# setting is the line before this file: `file="~/Notes/Inbox.md"` — a full path or one under ~; empty means Reminders.
# The file is made when it is missing; its folder must exist. The button's command (item.json):
#   "file=\"\"   # ← …\n@file:append.zsh"
#
# The reminder is added through EventKit by a JavaScript for Automation program, as the Reminders page's buttons add
# theirs: nothing is launched, and it reaches Reminders and the user's other devices (iCloud) by itself, with no date.
# The text goes to it in the environment, never on a command line. The first time, macOS asks whether the agent may
# have full access to your reminders (EventKit has no add-only access); the tap waits up to 45 s for the answer.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "To Inbox: zsh module datetime is missing"; exit 1 }

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
  print -ru2 -- "To Inbox: $2"
  exit 1
}

# ---- the text: one task, so its lines are joined with spaces ----
text=${DESMAPTIC_INPUT//$'\r'/}
text=${text//$'\n'/ }
text=${${text##[[:space:]]#}%%[[:space:]]#}
[[ -n $text ]] || fail other "Nothing to write: the text is empty"

if [[ -z $file ]]; then
  # ---- no file: a reminder in the default list ----
  # Prints "ok", or "!<why not>": !blank !unanswered !denied !nolist !readonly !save <code> !error <what>.
  read -r -d '' reminder_js <<'JS'
ObjC.import("Foundation");
ObjC.import("EventKit");

const REMINDER = 1;                                   // EKEntityTypeReminder
const NOT_DETERMINED = 0, FULL_ACCESS = 3;            // EKAuthorizationStatus
function access() { return Number($.EKEventStore.authorizationStatusForEntityType(REMINDER)); }

// One line: control and invisible characters become spaces, runs of white space one space.
function oneLine(s) {
  return s.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u2064\ufeff]+/g, " ").replace(/\s+/g, " ").trim();
}
// At most n characters (whole characters: an emoji is never split), with … when cut.
function cut(s, n) {
  const chars = Array.from(s);
  return chars.length <= n ? s : chars.slice(0, n - 1).join("") + "\u2026";
}

function run(argv) {
  try {
    // The text, from the environment: `system attribute` would garble its letters outside ASCII.
    const given = $.NSProcessInfo.processInfo.environment.objectForKey("INBOX_TEXT");
    const text = oneLine(given.isNil() ? "" : given.js);
    if (text === "") return "!blank";
    // A title of up to 200 characters; a longer text goes whole into the notes as well, so nothing is lost.
    const title = cut(text, 200);

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
    reminder.setTitle(title);
    if (title !== text) reminder.setNotes(cut(text, 20000));
    // The NSError comes back in $(): reading a Ref() after an error crashes osascript (EXC_BAD_ACCESS, macOS 26).
    const error = $();
    if (!store.saveReminderCommitError(reminder, true, error)) return "!save " + (error.isNil() ? "?" : error.code);
    return "ok";
  } catch (e) {
    return "!error " + e;
  }
}
JS
  answer=$(INBOX_TEXT=$text /usr/bin/osascript -l JavaScript -e "$reminder_js" 2>&1)
  case $answer in
    (ok) ;;
    ('!blank')      fail other "Nothing to write: the text is empty" ;;
    ('!unanswered') fail permission "macOS is still asking whether the agent may use Reminders: answer at the Mac, then tap again" ;;
    ('!denied')     fail permission "Allow the agent in System Settings → Privacy & Security → Reminders, or set an inbox file in this button’s settings" ;;
    ('!nolist')     fail config "Reminders has no default list: choose one in Reminders › Settings" ;;
    ('!readonly')   fail config "The default list of Reminders can’t take new reminders: choose another in Reminders › Settings" ;;
    ('!save '*)     fail other "The reminder was not saved (EventKit error ${answer#!save })" ;;
    (*)             fail other "The reminder was not added: ${answer#!}" ;;
  esac
else
  # ---- a file: one task line at its end ----
  case $file in
    '~')   file=$HOME ;;
    '~/'*) file=$HOME/${file#'~/'} ;;
  esac
  [[ $file == /* ]] || fail config "Not a full path: $file (start it with / or ~/)"
  [[ -d $file ]] && fail config "$file is a folder: name a file in it, such as Inbox.md"
  [[ -d ${file:h} ]] || fail notFound "No such folder: ${file:h}"
  strftime -s now '%H:%M' $EPOCHSECONDS

  # A file that does not end with a line break would glue the new task onto its last line.
  nl=""
  [[ -s $file && -n $(tail -c 1 -- "$file" 2>/dev/null) ]] && nl=$'\n'
  print -r -- "$nl- [ ] $now $text" >> "$file" 2>/dev/null || fail permission "Could not write to $file"
fi

# ---- a moment of ✓ on the button, then its own face again ----
call update-button "{\"cellId\":\"$cell\",\"icon\":\"checkmark\"}" >/dev/null
sleep 1.5
call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
exit 0
