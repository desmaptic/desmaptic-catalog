# Reminders › Complete, Tomorrow (and Next Week), Flag, Show Info and Overdue to Today: an item of Reminders' Edit or File
# menu, pressed through the Accessibility API from JavaScript for Automation — no Apple event, so no Automation question,
# only the Accessibility Desmaptic Agent already has. They act on the reminders selected in Reminders — Overdue to Today on
# the overdue ones of the list shown — so the button refuses while Reminders is not in front, and says so when the item is
# greyed out (nothing selected, nothing overdue there) instead of pressing for nothing.
# A key would not tell: it would go to whatever app is in front, and with text selected ⇧⌘F would reach the Spotlight
# service before Reminders' Flag (Reminders › Services comes first in the menu bar). It never launches Reminders.
#
# Reminders 7.0 (macOS 26), Base.lproj/MainMenu.nib: its items have no identifier of their own — AppKit then names a
# nib item "_NS:<number>", which says nothing — so an item is found by its shortcut, the same in every language:
#   Edit › Mark as Completed ⇧⌘C (markAsCompleted:)       Edit › Flag ⇧⌘F (toggleFlagged:)
#   Edit › Mark Due Date As › Tomorrow ⌥⌘T, › Next Week ⌥⌘K (postponeSelectionToTomorrow:, …ToStartOfWeekday:) — "Mark
#   Deadline As" in British English; they are greyed out, and Complete, Flag and Show Info are not in the menu at all,
#   while no reminder is selected (read on the running app, 2026-09-27; File then has Show List Info ⌘I).
#   File › Show Info ⌘I (showInfo:)
#   Edit › Mark Due Date As › Mark All Overdue to Today ⌃⌘T (postponeAllOverdueToToday:) — read 2026-10-12 from the nib.
# Each shortcut is unique in its menu (⌘C is Copy, ⌘T Today). The script looks in the
# menu it means (File is the 3rd item of the menu bar, Edit the 4th, counting the Apple menu), one level of submenus
# deep, then in the other two of File, Edit and View should a version move the item — never anywhere else.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=complete\n@file:menu/press.zsh"   — complete, tomorrow, next-week, flag, info or overdue.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
# where: the menu bar item (2 File, 3 Edit); key: the shortcut's character as Accessibility reports it (upper case);
# mods: its modifiers besides ⌘ as Accessibility counts them (1 ⇧, 2 ⌥, 4 ⌃); need: what the user does before a tap.
need="select a reminder"
case $action in
  complete)  where=3 key=C mods=1 name="Mark as Completed" ;;   # Edit › Mark as Completed ⇧⌘C
  tomorrow)  where=3 key=T mods=2 name="Tomorrow" ;;            # Edit › Mark Deadline As › Tomorrow ⌥⌘T
  next-week) where=3 key=K mods=2 name="Next Week" ;;           # Edit › Mark Deadline As › Next Week ⌥⌘K
  flag)      where=3 key=F mods=1 name="Flag" ;;                # Edit › Flag ⇧⌘F
  info)      where=2 key=I mods=0 name="Show Info" ;;           # File › Show Info ⌘I
  overdue)   where=3 key=T mods=4 name="Mark All Overdue to Today" need="open a list with overdue reminders (Today shows them all)" ;;
  *) print -u2 -- "Reminders: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not by process name: an iOS simulator runs its own "Reminders" under this account, and pgrep would
# take it for the Mac's. lsappinfo prints the pid of this account's Reminders app, nothing when it is not running.
[[ $(lsappinfo info -only pid -app com.apple.reminders 2>/dev/null) == *'"pid"='<1->* ]] \
  || { print -u2 -- "Reminders is not running"; exit 1 }

# Prints "ok", or !closed !behind !missing "!greyed <item>" !ax !busy "!press <error>" "!error <what>".
read -r -d '' press_js <<'JS'
ObjC.import("AppKit");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCreateSystemWide", ["id", []]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);
ObjC.bindFunction("AXUIElementSetMessagingTimeout", ["int", ["id", "float"]]);

// The Accessibility calls. An error other than "no Accessibility" (-25211) or "Reminders did not answer" (-25204) is
// "no such attribute": null. The value is read only after success — reading a Ref() after an error crashes osascript.
function get(element, name) {
  const value = Ref();
  const error = $.AXUIElementCopyAttributeValue(element, $(name), value);
  if (error == 0) return value[0];
  if (error == -25211) throw "ax";
  if (error == -25204) throw "busy";
  return null;
}
function text(element, name) {
  const value = get(element, name);
  if (value === null) return "";
  const s = ObjC.unwrap(value);
  return typeof s == "string" ? s : "";
}
function number(element, name) {
  const value = get(element, name);
  if (value === null) return null;
  const n = ObjC.unwrap(value);
  return typeof n == "number" ? n : null;
}
function list(element, name) { const value = get(element, name); return value === null ? [] : value; }
// The length of an NSArray (a JavaScript [] counts 0): read as a number — an empty NSArray's "count" is not falsy.
function count(array) { return Array.isArray(array) ? array.length : Number(array.count) || 0; }
function flag(element, name) { const value = get(element, name); return value !== null && ObjC.unwrap(value) === true; }

function remindersApp() {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("com.apple.reminders");
  for (let i = 0; i < count(apps); i++) {
    const app = apps.objectAtIndex(i);
    if (app.finishedLaunching) return $.AXUIElementCreateApplication(app.processIdentifier);
  }
  return null;
}
// The items of a menu bar item's menu, or of a menu item's submenu (none: []).
function itemsOf(element) {
  const menus = list(element, "AXChildren");
  return count(menus) ? list(menus.objectAtIndex(0), "AXChildren") : [];
}
function matches(item, key, mods) {
  return text(item, "AXMenuItemCmdChar").toUpperCase() == key && number(item, "AXMenuItemCmdModifiers") === mods;
}
// The item with this shortcut among `items`, or in one of their submenus.
function findIn(items, key, mods) {
  for (let i = 0; i < count(items); i++) if (matches(items.objectAtIndex(i), key, mods)) return items.objectAtIndex(i);
  for (let i = 0; i < count(items); i++) {
    const sub = itemsOf(items.objectAtIndex(i));
    for (let j = 0; j < count(sub); j++) if (matches(sub.objectAtIndex(j), key, mods)) return sub.objectAtIndex(j);
  }
  return null;
}
function press(where, key, mods) {
  try {
    const app = remindersApp();
    if (app === null) return "!closed";
    // A menu command acts on Reminders' key window, which it has only while it is in front.
    if (!flag(app, "AXFrontmost")) return "!behind";
    const bar = get(app, "AXMenuBar");
    if (bar === null) return "!missing";
    const tops = list(bar, "AXChildren");
    let item = null;
    for (const i of [where].concat([2, 3, 4].filter((i) => i != where))) {
      if (i >= count(tops)) continue;
      item = findIn(itemsOf(tops.objectAtIndex(i)), key, mods);
      if (item !== null) break;
    }
    if (item === null) return "!missing";
    if (!flag(item, "AXEnabled")) return "!greyed " + text(item, "AXTitle");
    const error = $.AXUIElementPerformAction(item, $("AXPress"));
    if (error == -25211) return "!ax";
    if (error != 0 && error != -25204) return "!press " + error;   // -25204: Reminders took it and is busy
    return "ok";
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
function run(argv) {
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 2);   // for every call: 2 s, not 6
  return press(parseInt(argv[0], 10), argv[1], parseInt(argv[2], 10));
}
JS

answer=$(/usr/bin/osascript -l JavaScript -e "$press_js" $where $key $mods 2>&1)
case $answer in
  ok)          exit 0 ;;
  '!closed')   print -u2 -- "Reminders is not running" ;;
  '!behind')   print -u2 -- "Reminders is not in front: bring it forward, $need, then tap again" ;;
  '!greyed '*) print -ru2 -- "\"${answer#!greyed }\" is not available in Reminders now: $need first" ;;
  '!missing')  print -ru2 -- "Reminders shows no \"$name\" now: $need first" ;;
  '!ax')       print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
  '!busy')     print -u2 -- "Reminders did not answer" ;;
  *)           print -ru2 -- "Reminders' menu did not respond: ${answer#!}" ;;
esac
exit 1
