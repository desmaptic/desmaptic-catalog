# Xcode › Test Again and Refresh Canvas: presses an item of a submenu of Xcode's menu bar through the Accessibility API —
# Product › Perform Action › Test Again (⌃⌥⌘G), Editor › Canvas › Refresh Canvas (⌥⌘P). Both work only in some states
# (tests were run in this window; a SwiftUI file shows its canvas), and a key sent into a greyed-out item would do
# nothing and say nothing: the press refuses with the reason instead. No Apple event, so no Automation question; it
# needs the Accessibility Desmaptic Agent has, works on every keyboard layout and never launches Xcode. Like the
# shortcuts, it works only with Xcode in front.
# Every button's command is one line that names the item, then this file (app.json):
#   "menu=Product sub='Perform Action' item='Test Again'\n@file:menu/press.zsh"
# Xcode is not localized: its menus are in English everywhere, so the items are found by their English names.
# Read from the bundles of Xcode 27.0, the same in Xcode 27.1 beta (2026-10-12), not from the running app: Test Again
# (testAgain:, ⌃⌥⌘G) sits in the Perform Action submenu of Product; Refresh Canvas (refreshCanvas:, ⌥⌘P) in the Canvas
# submenu of the source editor's Editor menu. No item has been pressed live yet.
emulate -R zsh
[[ -n $menu && -n $sub && -n $item ]] || { print -u2 -- "Xcode: the button names no menu item"; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
label="$menu › $sub › $item"

# pgrep sees every account's processes; -U keeps it to this one.
pgrep -xqU $UID Xcode || { print -u2 -- "Xcode is not running"; exit 1 }

# Prints "ok", or !closed !behind !missing !greyed !ax !busy. The value of an attribute is read only after the call
# succeeded: reading a Ref() after an error crashes osascript.
read -r -d '' press <<'JS'
ObjC.import("AppKit");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCreateSystemWide", ["id", []]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);
ObjC.bindFunction("AXUIElementSetMessagingTimeout", ["int", ["id", "float"]]);

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
function list(element, name) { const value = get(element, name); return value === null ? [] : value; }
function flag(element, name) { const value = get(element, name); return value !== null && ObjC.unwrap(value) === true; }
// The first child of `parent` titled `name`, or null; `from` skips the Apple menu of the menu bar.
function child(parent, name, from) {
  const items = list(parent, "AXChildren");
  for (let i = from; i < Number(items.count); i++) {
    if (text(items.objectAtIndex(i), "AXTitle") == name) return items.objectAtIndex(i);
  }
  return null;
}
// The menu a menu-bar item or a submenu item opens, or null. JXA hands an NSArray's count over as a string.
function menuOf(item) {
  if (item === null) return null;
  const menus = list(item, "AXChildren");
  return Number(menus.count) > 0 ? menus.objectAtIndex(0) : null;
}
// Xcode in front: the running Xcode that is the active app (Xcode and an Xcode beta share the bundle id).
function frontXcode() {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("com.apple.dt.Xcode");
  if (Number(apps.count) == 0) return "!closed";
  for (let i = 0; i < Number(apps.count); i++) {
    const app = apps.objectAtIndex(i);
    if (app.active) return $.AXUIElementCreateApplication(app.processIdentifier);
  }
  return "!behind";
}
function run(argv) {
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 3);
  try {
    const app = frontXcode();
    if (typeof app == "string") return app;
    const bar = get(app, "AXMenuBar");
    if (bar === null) return "!missing";
    const submenu = menuOf(child(menuOf(child(bar, argv[0], 1)), argv[1], 0));
    const item = submenu === null ? null : child(submenu, argv[2], 0);
    if (item === null) return "!missing";
    if (!flag(item, "AXEnabled")) return "!greyed";
    const error = $.AXUIElementPerformAction(item, $("AXPress"));
    if (error == -25211) return "!ax";
    return (error == 0 || error == -25204) ? "ok" : "!press " + error;   // -25204: Xcode took it and is busy
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
JS

case $item in
  'Test Again')     why="run tests in this Xcode window first" ;;
  'Refresh Canvas') why="open a SwiftUI file and show its canvas first" ;;
  *)                why="Xcode does not offer it here" ;;
esac
answer=$(osascript -l JavaScript -e "$press" "$menu" "$sub" "$item" 2>&1)
case $answer in
  ok) exit 0 ;;
  '!closed')  print -u2 -- "Xcode is not running" ;;
  '!behind')  print -u2 -- "Xcode is not in front: bring it forward first" ;;
  '!missing') print -ru2 -- "Xcode shows no $label now: $why" ;;
  '!greyed')  print -ru2 -- "$label is not available in Xcode now: $why" ;;
  '!ax')      print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
  '!busy')    print -u2 -- "Xcode did not answer" ;;
  *)          print -ru2 -- "Xcode’s menu did not respond: ${${answer##*execution error: }[1,200]}" ;;
esac
exit 1
