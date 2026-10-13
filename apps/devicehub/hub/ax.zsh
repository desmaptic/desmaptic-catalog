# Device Hub › the menu buttons' shared part: $hub_ax, a JavaScript for Automation program that finds an item of Device
# Hub's menus and presses it through the Accessibility API itself — no Apple events, so no Automation question, only
# the Accessibility Desmaptic Agent already has. It never launches Device Hub: it asks macOS for the running app by
# bundle id and answers "!closed" when there is none. Functions and data only; the button's own line comes first and
# press.zsh after this file runs it (app.json):
#   "action=press menu=Controls item=Home\n@file:hub/ax.zsh\n@file:hub/press.zsh"
#   "action=press menu=Device sub=Keyboard item='Toggle Software Keyboard'\n@file:hub/ax.zsh\n@file:hub/press.zsh"
#
# What Device Hub 27.0 (255.2.6.6, inside Xcode 27.0) has, read from its bundle and from the running app (2026-09-27):
# - Its menus are English in every language: the app bundle and DeviceKit.framework ship only en.lproj. So an item is
#   found by its English name; its items carry no identifier of their own (AXIdentifier is empty), and SwiftUI puts
#   no identifier on the menus either.
# - Controls (a menu of the menu bar): Home ⇧⌘H, Lock ⌘L, Siri, App Switcher ⇧⌃⌘H, Action Button, Rotate Left, Rotate
#   Right, Screenshot ⇧⌘S, Record Screen ⇧⌘R (named "Stop Recording" while it records). Device: Keyboard › Toggle
#   Software Keyboard ⌥⌘K, Appearance › Toggle Appearance ⇧⌘A, Accessibility › Increase / Decrease Text Size ⌥⌘+ ⌥⌘-,
#   Location (not on the page). Rotate Left and Right are shown only for a device that turns
#   (their names are in DeviceKit's code, next to RotateLeftMenuItemProvider; with no device in front they are hidden).
# - They act on the device of Device Hub's key window, so while Device Hub is in the background every one of them is
#   greyed out (read 2026-09-27 with Device Hub behind another app and an iPhone simulator window open): a press brings
#   Device Hub forward first — raising its main window, the one it last used — and then waits up to 1.5 s for the
#   item to be there and enabled, since the menus follow the key window a moment after Device Hub comes forward.
#   One press ran on 2026-09-27 (a Location item, from the background): Device Hub came forward within the second and
#   the item was enabled within the 1.5 s. No other item has been pressed yet.
# - With Stage Manager on, AXWindows of Device Hub is empty; AXMainWindow still names its window.
# - Device Hub may pass keys to the device while its window captures the keyboard: a menu press is never taken for a
#   key, and it works on every keyboard layout.
#
# Modes (the arguments; data never goes into the program text):
#   press <menu> <submenu> <names> → presses menu › [submenu ›] item, the item being the first whose name is one of
#                    <names> ("Record Screen|Stop Recording"); <submenu> "" for none: "ok", or !closed !behind !missing
#                    !greyed !ax !busy
#   title          → the title of Device Hub's front window, read without bringing it forward ("iPhone 17 Pro – iOS
#                    27.0"; "" with no window), or !closed !ax !busy — Shake reads it (shake.zsh), nothing is pressed
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
read -r -d '' hub_ax <<'JS'
ObjC.import("AppKit");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCreateSystemWide", ["id", []]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementSetAttributeValue", ["int", ["id", "id", "id"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);
ObjC.bindFunction("AXUIElementSetMessagingTimeout", ["int", ["id", "float"]]);

// The Accessibility calls. An error other than "no Accessibility" (-25211) or "Device Hub did not answer" (-25204) is
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
function list(element, name) { const value = get(element, name); return value === null ? [] : value; }
function flag(element, name) { const value = get(element, name); return value !== null && ObjC.unwrap(value) === true; }
function perform(element, action) {
  const error = $.AXUIElementPerformAction(element, $(action));
  if (error == -25211) throw "ax";
  return error;   // -25204 after a press: Device Hub took it and is busy — the press happened
}
function set(element, name, value) {
  const error = $.AXUIElementSetAttributeValue(element, $(name), value);
  if (error == -25211) throw "ax";
}

function hubApp() {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("com.apple.dt.Devices");
  for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i);
    if (app.finishedLaunching) return $.AXUIElementCreateApplication(app.processIdentifier);
  }
  return null;
}
// The menu of a menu-bar item or of a submenu item, or null. JXA hands an NSArray's count over as a string, and "0" is
// true in JavaScript: compare it as a number (a plain item's AXChildren is an empty array).
function menuOf(item) {
  const menus = list(item, "AXChildren");
  return Number(menus.count) > 0 ? menus.objectAtIndex(0) : null;
}
// The first item of `menu` whose name is one of `names`, or null. Hidden items are not in the list at all.
function childNamed(menu, names) {
  const items = list(menu, "AXChildren");
  for (let i = 0; i < items.count; i++) {
    if (names.includes(text(items.objectAtIndex(i), "AXTitle"))) return items.objectAtIndex(i);
  }
  return null;
}
// The menu `title` of the menu bar (never the Apple menu), then its submenu `sub` when one is given, or null.
function findMenu(app, title, sub) {
  const bar = get(app, "AXMenuBar");
  if (bar === null) return null;
  const tops = list(bar, "AXChildren");
  let menu = null;
  for (let i = 1; i < tops.count && menu === null; i++) {
    if (text(tops.objectAtIndex(i), "AXTitle") == title) menu = menuOf(tops.objectAtIndex(i));
  }
  if (menu === null || !sub) return menu;
  const item = childNamed(menu, [sub]);
  return item === null ? null : menuOf(item);
}
// Device Hub in front, its main window raised (and taken out of the Dock): true once Device Hub itself says it is the
// active app, false when it has not within a second.
function bringForward(app) {
  if (flag(app, "AXFrontmost")) return true;
  let window = get(app, "AXMainWindow");
  if (window === null) window = get(app, "AXFocusedWindow");
  if (window !== null) {
    if (flag(window, "AXMinimized")) set(window, "AXMinimized", $.NSNumber.numberWithBool(false));
    perform(window, "AXRaise");
  }
  set(app, "AXFrontmost", $.NSNumber.numberWithBool(true));
  for (let tries = 0; tries < 20; tries++) {
    if (flag(app, "AXFrontmost")) return true;
    delay(0.05);
  }
  return false;
}
// Waits up to 1.5 s for menu › [sub ›] one of `names` to be there and enabled, then presses it.
function pressItem(app, title, sub, names) {
  for (let tries = 0; ; tries++) {
    const menu = findMenu(app, title, sub);
    const item = menu === null ? null : childNamed(menu, names);
    if (item !== null && flag(item, "AXEnabled")) {
      const error = perform(item, "AXPress");
      return (error == 0 || error == -25204) ? "ok" : "!press " + error;
    }
    if (tries == 15) return item === null ? "!missing" : "!greyed";
    delay(0.1);
  }
}
function press(title, sub, names) {
  try {
    const app = hubApp();
    if (app === null) return "!closed";
    if (!bringForward(app)) return "!behind";
    return pressItem(app, title, sub, names);
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
// The title of the window Device Hub has in front — its main window, else its focused one — read in the background
// too, without bringing Device Hub forward: "iPhone 17 Pro – iOS 27.0" for a device window, "" when it has none.
function title() {
  try {
    const app = hubApp();
    if (app === null) return "!closed";
    for (const name of ["AXMainWindow", "AXFocusedWindow"]) {
      const window = get(app, name);
      if (window !== null) return text(window, "AXTitle");
    }
    return "";
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
function run(argv) {
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 3);   // for every call: 3 s, not 6
  switch (argv[0]) {
    case "title":
      return title();
    case "press":
      return (argv.length == 4 && argv[1] && argv[3]) ? press(argv[1], argv[2], argv[3].split("|"))
        : "!error press needs <menu> <submenu> <names>";
    default:
      return "!error mode " + argv[0];
  }
}
JS
