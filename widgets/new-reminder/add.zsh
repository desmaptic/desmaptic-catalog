#!/bin/zsh
# Reminder tap: the text typed on the phone ($DESMAPTIC_INPUT) becomes a reminder in the default list (Reminders ›
# Settings › Default list), with no date. Its first line that is not blank is the title (up to 200 characters; a longer
# one puts the whole text in the notes, so nothing is lost), the rest the notes; a text that is one web address also
# becomes the reminder's link. It is added through EventKit by a JavaScript for Automation program — the stock osascript
# is all it needs — not through the Reminders app: nothing is launched, and the reminder reaches Reminders and the user's
# other devices as any reminder added by another app does. The text reaches the program through its environment, read
# by Foundation as UTF-8, never through its arguments or its code.
# The first time, macOS asks whether the agent may have full access to your reminders (EventKit has no add-only access
# for reminders); the tap waits up to 45 s for the answer.
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
  print -ru2 -- "Reminder: $2"
  exit 1
}

[[ -n ${DESMAPTIC_INPUT//[[:space:]]/} ]] || fail other "Nothing to remind of: the text is empty"

# Prints "ok", or "!<why not>": !blank !unanswered !denied !nolist !readonly !save <code> !error <what>.
read -r -d '' js <<'JS'
ObjC.import("Foundation");
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
  return chars.length <= n ? s : chars.slice(0, n - 1).join("") + "…";
}
const WEB = /^https?:\/\/[^\s"'<>\\^`{|}]+$/i;

function run() {
  try {
    const value = $.NSProcessInfo.processInfo.environment.objectForKey("DESMAPTIC_INPUT");
    const all = (value.isNil() ? "" : value.js).replace(/\r\n?|[\u0085\u2028\u2029]/g, "\n");
    const lines = all.split("\n");
    const first = lines.findIndex((line) => oneLine(line) !== "");
    if (first < 0) return "!blank";
    const whole = oneLine(lines[first]);
    const title = cut(whole, 200);
    const notes = cut(tidy(title === whole ? lines.slice(first + 1).join("\n") : lines.slice(first).join("\n")), 20000);
    const trimmed = all.trim();
    const link = (WEB.test(trimmed) && trimmed.length <= 4096) ? trimmed : "";

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
    if (notes) reminder.setNotes(notes);
    if (link) {
      const url = $.NSURL.URLWithString(link);
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

answer=$(osascript -l JavaScript -e "$js" 2>&1)
case $answer in
  ok) ;;
  '!blank')      fail other "Nothing to remind of: the text is only spaces" ;;
  '!unanswered') fail permission "macOS is still asking whether the agent may use Reminders" ;;
  '!denied')     fail permission "Allow the agent in System Settings → Privacy & Security → Reminders" ;;
  '!nolist')     fail config "There is no default list: choose one in Reminders › Settings" ;;
  '!readonly')   fail config "The default list can’t take new reminders: choose another in Reminders › Settings" ;;
  '!save '*)     fail other "The reminder was not saved (EventKit error ${answer#!save })" ;;
  *)             fail other "The reminder was not added: ${answer#!}" ;;
esac

# ---- a moment of ✓ on the button, then its own face again ----
call update-button "{\"cellId\":\"$cell\",\"icon\":\"checkmark\"}" >/dev/null
sleep 1.5
call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
exit 0
