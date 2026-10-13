# Notes › the menu buttons: an item of Notes' File, Edit, Format or View menu, pressed through the Accessibility API from
# JavaScript for Automation — no Apple event, so no Automation question, only the Accessibility Desmaptic Agent already
# has. A key would not tell whether it did anything, would go to whatever app is in front, and with text selected
# ⇧⌘L would reach the "Search With Google" service before Notes' Checklist (Notes › Services comes first in the menu
# bar); a press works on every keyboard layout.
# Two kinds of buttons:
#   bring — New Note, Search (and its long press, Find), Folders, Gallery View, List View: they bring Notes to the
#           front first (`open -b`, Launch Services: it starts Notes when it is closed and opens its window again when
#           it was closed; still behind after 2 s, Accessibility raises its window and makes it the front app, as on
#           the Device Hub page), then wait for the item, since Notes greys out every item while it is in the
#           background (read 2026-09-28: with Notes behind, even File › New Note was greyed out).
#   need  — Pin Note, Add Link, Checklist, Mark as Checked, Table, Title, Heading, Subheading, Body: they act on the
#           note being written, so they refuse while Notes is not in front, and say why when the item is greyed out
#           (no note open, the cursor not in a checklist) instead of pressing for nothing. They never launch Notes.
#
# Notes 4.13 (3146.141.6, macOS 26), read 2026-09-28 from Base.lproj/MainMenu.nib and from the running app's menus
# (read only: no item was pressed). Its items have no identifier of their own — AppKit then names a nib item
# "_NS:<number>", which says nothing — so an item is found by its shortcut, the same in every language:
#   File › New Note ⌘N                                   Edit › Find › Note List Search… ⌥⌘F, › Find… ⌘F
#   View › Hide Folders ⌃⌘S (Show Folders while hidden)   View › as List ⌘1, › as Gallery ⌘2 (the 1st and 2nd items)
#   Edit › Add Link… ⌘K                                   Format › Checklist ⇧⌘L, › Mark as Checked ⇧⌘U ("Mark as
#   Format › Title ⇧⌘T, › Heading ⇧⌘H, › Subheading ⇧⌘J,   Ticked" in British English; Mark as Unchecked on a ticked
#            › Body ⇧⌘B, › Table ⌥⌘T                       item)
# Each shortcut is unique in these four menus (⌘U is Underline, ⌘T Show Fonts, ⌘B Bold, ⌘J Jump to Selection, ⌃⌘K Show
# Note Activity). The digits are the exception: AppKit localizes key equivalents in Notes' nib (the flag is on), so ⌘1
# may show as another key on a layout where 1 needs ⇧ (French) — as List and as Gallery are found by their place, the
# 1st and 2nd items of View, when they carry a ⌘-only shortcut there, and by the shortcut otherwise.
# File › Pin Note has no shortcut: it is found by its name, "Pin Note" or "Unpin Note" — or "Pin Notes" / "Unpin Notes",
# which Notes keeps next to them for several selected notes — in each of Notes' languages (MainMenu.loctable and
# Localizable.loctable of Notes 4.13 — the list below; none of them names another menu item), in File only.
# The script looks in the menu it means (File is the 3rd item of the menu bar, Edit the 4th, Format the 5th, View the
# 6th, counting the Apple menu), one level of submenus deep, then in the other three — never anywhere else.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=checklist\n@file:menu/press.zsh"   — new, search, find, folders, gallery, list, pin, link, checklist,
#                                                check, table, title, heading, subheading or body.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
# front: bring or need (above); where: the menu bar item (2 File, 3 Edit, 4 Format, 5 View); key: the shortcut's
# character as Accessibility reports it (upper case); mods: its modifiers besides ⌘ as Accessibility counts them
# (1 ⇧, 2 ⌥, 4 ⌃); place: the item's place in its menu to try first (-1: none); hint: what to do when it is greyed out.
place=-1
case $action in
  new)        front=bring where=2 key=N mods=0 name="New Note"          hint="open a folder you can add notes to" ;;
  search)     front=bring where=3 key=F mods=2 name="Note List Search"  hint="close the dialog open in Notes" ;;
  find)       front=bring where=3 key=F mods=0 name="Find"              hint="open a note" ;;
  folders)    front=bring where=5 key=S mods=4 name="Hide Folders"      hint="close the dialog open in Notes" ;;
  list)       front=bring where=5 key=1 mods=0 name="as List" place=0   hint="close the dialog open in Notes" ;;
  gallery)    front=bring where=5 key=2 mods=0 name="as Gallery" place=1 hint="close the dialog open in Notes" ;;
  pin)        front=need  where=2 key="" mods=8 name="Pin Note"         hint="select a note" ;;
  link)       front=need  where=3 key=K mods=0 name="Add Link"          hint="put the cursor in a note" ;;
  checklist)  front=need  where=4 key=L mods=1 name="Checklist"         hint="put the cursor in a note" ;;
  check)      front=need  where=4 key=U mods=1 name="Mark as Checked"   hint="put the cursor on a checklist item" ;;
  table)      front=need  where=4 key=T mods=2 name="Table"             hint="put the cursor in a note" ;;
  title)      front=need  where=4 key=T mods=1 name="Title"             hint="put the cursor in a note" ;;
  heading)    front=need  where=4 key=H mods=1 name="Heading"           hint="put the cursor in a note" ;;
  subheading) front=need  where=4 key=J mods=1 name="Subheading"        hint="put the cursor in a note" ;;
  body)       front=need  where=4 key=B mods=1 name="Body"              hint="put the cursor in a note" ;;
  *) print -u2 -- "Notes: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [[ $front == bring ]]; then
  # Launch Services brings the running Notes forward (showing it again when hidden, opening its window when it was
  # closed) and starts it when it is closed. No permission needed.
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.apple.Notes 2>/dev/null || { print -u2 -- "Notes did not open"; exit 1 }
else
  # By bundle id, not by process name: an iOS simulator runs its own "MobileNotes" under this account, and a web app
  # saved from Safari may be named Notes too. lsappinfo prints the pid of this account's Notes, nothing when it is not
  # running.
  [[ $(lsappinfo info -only pid -app com.apple.Notes 2>/dev/null) == *'"pid"='<1->* ]] \
    || { print -u2 -- "Notes is not running"; exit 1 }
fi

# Prints "ok", or !closed !behind !missing "!greyed <item>" !ax !busy "!press <error>" "!error <what>".
read -r -d '' press_js <<'JS'
ObjC.import("AppKit");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCreateSystemWide", ["id", []]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);
ObjC.bindFunction("AXUIElementSetAttributeValue", ["int", ["id", "id", "id"]]);
ObjC.bindFunction("AXUIElementSetMessagingTimeout", ["int", ["id", "float"]]);

// File › Pin Note and, on a pinned note, Unpin Note — Pin Notes and Unpin Notes with several notes selected — in every
// language of Notes 4.13.
const PIN = ["Afixar nota", "Afixar notas", "Deixa de fixar la nota", "Deixa de fixar notes",
  "Dejar de destacar nota", "Dejar de destacar notas", "Desafixar Nota", "Desafixar Notas", "Desafixar nota",
  "Desafixar notas", "Desfijar nota", "Desfijar notas", "Destacar nota", "Destacar notas", "Detașează notița",
  "Detașează notițele", "Désépingler la note", "Détacher la note", "Détacher les notes", "Fastgør note",
  "Fastgør noter", "Fest notat", "Fest notater", "Fijar nota", "Fijar notas", "Fixa la nota", "Fixa les notes",
  "Fixar Nota", "Fixar Notas", "Fixați notița", "Fixați notițele", "Frigør note", "Frigør noter", "Ghim các ghi chú",
  "Ghim ghi chú", "Gỡ ghim các ghi chú", "Gỡ ghim ghi chú", "In evidenza", "Irrota muistiinpano",
  "Irrota muistiinpanot", "Jegyzet rögzítése", "Jegyzet rögzítésének feloldása", "Jegyzetek rögzítése",
  "Jegyzetek rögzítésének feloldása", "Kiinnitä muistiinpano", "Kiinnitä muistiinpanot", "Lepas Pin Catatan",
  "Lossa anteckning", "Lossa anteckningar", "Løsne notat", "Løsne notater", "Maak notitie los", "Maak notitie vast",
  "Maak notities los", "Maak notities vast", "Non in evidenza", "Nota in evidenza", "Note in evidenza",
  "Note non in evidenza", "Notiz anpinnen", "Notiz lösen", "Notizen anpinnen", "Notizen lösen", "Notları İğnele",
  "Notların İğnelerini Kaldır", "Notu İğnele", "Notun İğnesini Kaldır", "Nyahpin Nota", "Nåla fast anteckning",
  "Nåla fast anteckningar", "Odepnij notatki", "Odepnij notatkę", "Odepnout poznámku", "Odepnout poznámky",
  "Odopnúť poznámku", "Odopnúť poznámky", "Odpni zapisek", "Otkvači bilješke", "Otkvači bilješku", "Pin Catatan",
  "Pin Nota", "Pin Note", "Pin Notes", "Pinkan Nota", "Pripni zapisek", "Pripni zapiske", "Pripnúť poznámku",
  "Pripnúť poznámky", "Przypnij notatki", "Przypnij notatkę", "Připnout poznámku", "Připnout poznámky",
  "Přišpendlit poznámku", "Unpin Note", "Unpin Notes", "Zakvači bilješke", "Zakvači bilješku", "Épingler la note",
  "Épingler les notes", "Καρφίτσωμα σημείωσης", "Καρφίτσωμα σημειώσεων", "Ξεκαρφίτσωμα", "Відкріпити нотатки",
  "Відкріпити нотатку", "Закрепить заметки", "Закрепить заметку", "Закріпити нотатки", "Закріпити нотатку",
  "Открепить заметки", "Открепить заметку", "ביטול הצמדת הפתק", "ביטול הצמדת פתקים", "הצמדת הפתק", "הצמדת פתקים",
  "إلغاء تثبيت الملاحظات", "إلغاء تثبيت الملاحظة", "تثبيت الملاحظات", "تثبيت الملاحظة", "नोट अनपिन करें",
  "नोट पिन करें", "नोट्स अनपिन करें", "नोट्स पिन करें", "ปลดหมุดโน้ต", "ปักหมุดโน้ต", "メモのピン留めを解除", "メモをピンで固定",
  "メモをピン留め", "取消置顶备忘录", "取消釘選備忘錄", "置顶备忘录", "釘選備忘錄", "메모 고정", "메모 고정 해제"];

// The Accessibility calls. An error other than "no Accessibility" (-25211) or "Notes did not answer" (-25204) is
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
// The length of an NSArray (a JavaScript [] counts 0): read as a number — JXA hands "count" over as a string, and
// "0" is true.
function count(array) { return Array.isArray(array) ? array.length : Number(array.count) || 0; }
function flag(element, name) { const value = get(element, name); return value !== null && ObjC.unwrap(value) === true; }

function notesApp() {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("com.apple.Notes");
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
function hasShortcut(item, mods) {
  return text(item, "AXMenuItemCmdChar") !== "" && number(item, "AXMenuItemCmdModifiers") === mods;
}
// The first item that passes `test` among `items`, or in one of their submenus.
function findIn(items, test) {
  for (let i = 0; i < count(items); i++) if (test(items.objectAtIndex(i))) return items.objectAtIndex(i);
  for (let i = 0; i < count(items); i++) {
    const sub = itemsOf(items.objectAtIndex(i));
    for (let j = 0; j < count(sub); j++) if (test(sub.objectAtIndex(j))) return sub.objectAtIndex(j);
  }
  return null;
}
function find(app, where, key, mods, place) {
  const bar = get(app, "AXMenuBar");
  if (bar === null) return null;
  const tops = list(bar, "AXChildren");
  if (place >= 0 && where < count(tops)) {
    const items = itemsOf(tops.objectAtIndex(where));
    if (place < count(items) && hasShortcut(items.objectAtIndex(place), mods)) return items.objectAtIndex(place);
  }
  // Pin Note, found by its name, is looked for in File only; a shortcut in the other three menus too.
  const byName = key === "";
  const test = byName
    ? (item) => PIN.includes(text(item, "AXTitle"))
    : (item) => text(item, "AXMenuItemCmdChar").toUpperCase() == key && number(item, "AXMenuItemCmdModifiers") === mods;
  for (const i of byName ? [where] : [where].concat([2, 3, 4, 5].filter((i) => i != where))) {
    if (i >= count(tops)) continue;
    const item = findIn(itemsOf(tops.objectAtIndex(i)), test);
    if (item !== null) return item;
  }
  return null;
}
function press(front, where, key, mods, place) {
  try {
    let app = notesApp();
    let tries = 0;
    if (front == "bring") {
      // `open -b` came first: Notes may still be starting (up to 10 s), then coming forward (up to 4 s); its menus
      // follow the key window a moment later, so the item gets up to 3 s to be there and enabled.
      for (let t = 0; app === null && t < 100; t++) { delay(0.1); app = notesApp(); }
      if (app === null) return "!closed";
      let inFront = flag(app, "AXFrontmost");
      for (let t = 0; !inFront && t < 20; t++) { delay(0.1); inFront = flag(app, "AXFrontmost"); }
      // Still behind after 2 s: ask Accessibility too, as the Device Hub page does — its window raised (and out of
      // the Dock), Notes made the front app.
      if (!inFront) {
        let window = get(app, "AXMainWindow");
        if (window === null) window = get(app, "AXFocusedWindow");
        if (window !== null) {
          if (flag(window, "AXMinimized")) $.AXUIElementSetAttributeValue(window, $("AXMinimized"), $.NSNumber.numberWithBool(false));
          $.AXUIElementPerformAction(window, $("AXRaise"));
        }
        $.AXUIElementSetAttributeValue(app, $("AXFrontmost"), $.NSNumber.numberWithBool(true));
        for (let t = 0; !inFront && t < 20; t++) { delay(0.1); inFront = flag(app, "AXFrontmost"); }
      }
      if (!inFront) return "!behind";
      tries = 30;
    } else {
      if (app === null) return "!closed";
      // A menu command acts on Notes' key window, which it has only while it is in front.
      if (!flag(app, "AXFrontmost")) return "!behind";
    }
    for (let t = 0; ; t++) {
      const item = find(app, where, key, mods, place);
      if (item !== null && flag(item, "AXEnabled")) {
        const error = $.AXUIElementPerformAction(item, $("AXPress"));
        if (error == -25211) return "!ax";
        if (error != 0 && error != -25204) return "!press " + error;   // -25204: Notes took it and is busy
        return "ok";
      }
      if (t >= tries) return item === null ? "!missing" : "!greyed " + text(item, "AXTitle");
      delay(0.1);
    }
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
function run(argv) {
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 2);   // for every call: 2 s, not 6
  return press(argv[0], parseInt(argv[1], 10), argv[2], parseInt(argv[3], 10), parseInt(argv[4], 10));
}
JS

answer=$(/usr/bin/osascript -l JavaScript -e "$press_js" "$front" "$where" "$key" "$mods" "$place" 2>&1)
case $answer in
  ok)          exit 0 ;;
  '!closed')   print -u2 -- "Notes is not running" ;;
  '!behind')
    if [[ $front == bring ]]; then print -u2 -- "Notes did not come to the front"
    else print -ru2 -- "Notes is not in front: bring it forward, $hint, then tap again"; fi ;;
  '!greyed '*) print -ru2 -- "\"${answer#!greyed }\" is not available in Notes now: $hint first" ;;
  '!missing')  print -ru2 -- "Notes shows no \"$name\" now: $hint first" ;;
  '!ax')       print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
  '!busy')     print -u2 -- "Notes did not answer" ;;
  *)           print -ru2 -- "Notes' menu did not respond: ${answer#!}" ;;
esac
exit 1
