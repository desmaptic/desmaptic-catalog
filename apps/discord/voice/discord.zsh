# Discord › Mute and Deafen, the shared part: functions only — every script of these two buttons starts with this file
# (app.json): the live loop (live.zsh) and the tap (press.zsh).
#
# Discord (com.hnc.Discord) is an Electron window around its web client, with no AppleScript dictionary; ⇧⌘M and ⇧⌘D
# reach it only while it is in front. The two controls at the bottom left of its window — the microphone and the
# headphones next to your name — are web switches, and the Accessibility API reads and presses them from JavaScript for
# Automation: no Apple event, so never the Automation question, and a press lands in Discord's window without bringing
# it forward. Found in the web client (build of 2026-09-27, cached by Discord 0.0.411; read, never run): the account
# panel draws the Mute switch first and the Deafen switch second, both with role "switch", the class
# audioButtonWithMenu__<hash> and aria-checked = muted (selfMute, or deafened, or server-muted) / deafened (selfDeaf or
# server-deafened); the chevron next to each (the device menu) has another class. Accessibility shows each as an
# AXCheckBox (subrole AXSwitch) whose AXValue is 1 while muted / deafened and 0 while not, and its DOM classes as
# AXDOMClassList — the same in every language of Discord, where the label ("Mute", «Заглушить») is not. The switch is
# greyed out (AXEnabled 0) only while the voice state is handed to another device (awaitingRemote).
# Discord's own rules, from the same code: Mute while deafened undeafens you and turns the mic on; Deafen mutes the mic
# as well, and undeafening brings the mic back to what it was.
#
# Discord exposes its web content only to a client that asks for it (AXManualAccessibility on the app — Discord keeps
# it on until it quits), and the first read after asking may find nothing. What a read walks: Discord's windows
# (AXWindows), then each one depth first — one call per element (role, children, DOM classes; no text is ever read),
# skipping lists, trees, tables, text and buttons, which hold nothing of the panel — until both switches are found.
# The long-lived reader keeps the two it found and, while they are still the switches, reads only their values.
# A press through Accessibility also moves Discord's keyboard focus to the switch (seen on 0.0.411), and Space in
# Discord would then flip it again instead of typing: the tap finds what had the focus before (AXFocused reads true in
# the background too) and gives it back — or, when that was inside a list or not found, to the page itself.

# REPLY = the process id of this account's Discord; 1 when it is not running. lsappinfo asks Launch Services by bundle
# id: no permission, nothing Discord notices, and only this account's Discord.
discord_pid() {
  emulate -L zsh
  local out
  out=$(lsappinfo info -only pid -app com.hnc.Discord 2>/dev/null)
  REPLY=${${out#*\"pid\"=}%%[^0-9]*}
  [[ $out == *'"pid"='[0-9]* && $REPLY == <1-> ]]
}

# Keeps a state line in the file the two buttons share, when it is newer than the one there. A line is
# "<ms the read began> <discord> <mute> <deafen>" (the reader's words, below); a read that began earlier never replaces
# a later one — a tap writes what it saw after its press, and a read already running must not undo that.
discord_keep() {   # $1 shared folder, $2 the line
  emulate -L zsh
  local asked=${2%% *} old=""
  [[ -n $1 && $asked == <-> ]] || return 1
  zf_mkdir -p $1 2>/dev/null
  [[ -r $1/state ]] && read -r old < $1/state 2>/dev/null
  old=${old%% *}
  [[ $old == <-> ]] && (( old >= asked )) && return 0
  print -r -- "$2" > $1/state.$$ 2>/dev/null && zf_mv -f $1/state.$$ $1/state 2>/dev/null
}

# REPLY = the reader, a JavaScript for Automation program (osascript -l JavaScript -e "$REPLY" <mode> …):
#   read <pid>                   prints one line: <ms> <discord> <mute> <deafen> <elements visited>
#   loop <pid> <period> <idle> <seconds>
#                                a line per read: every <period> s while the switches are found, every <idle> s while
#                                they are not; ends after <seconds> (the bridge keeps every object it hands to
#                                JavaScript, so a long-lived reader grows) or without Accessibility. When Discord quits
#                                it says busy: the script, which asks lsappinfo, stops it
#   press <pid> <mute|deafen>    presses that switch. Prints nothing or !<why not> on the first line: !noax, !busy,
#                                !closed (no window), !none (no switches in the window), !greyed, !press <error>;
#                                then the state line once the switch has changed
# <discord>: ok (both switches found), none (a window, but no switches in it: settings open, a call popped out, Discord
# still starting), closed (no window: closed to the Dock), wait (its web content is not exposed yet), busy (Discord did
# not answer), noax (Desmaptic Agent has no Accessibility), off (not running). <mute>, <deafen>: on (muted / deafened),
# off, unknown (a value this reader does not know), - (not found).
discord_program() {
  read -r -d '' REPLY <<'JS'
ObjC.import("AppKit");
ObjC.import("ApplicationServices");

// The class Discord gives exactly the two switches of its account panel, Mute first, then Deafen, followed by a hash
// that changes with its builds: audioButtonWithMenu__5e764.
const CLASS = "audioButtonWithMenu";
// Nothing of the account panel lives under these: not walked.
const SKIP = { AXStaticText: 1, AXImage: 1, AXTable: 1, AXList: 1, AXOutline: 1, AXTextArea: 1, AXTextField: 1,
  AXComboBox: 1, AXHeading: 1, AXLink: 1, AXRow: 1, AXCell: 1, AXScrollBar: 1, AXMenu: 1, AXMenuBar: 1,
  AXButton: 1, AXRadioButton: 1, AXPopUpButton: 1, AXMenuButton: 1, AXSlider: 1, AXCheckBox: 1 };
const WALK = $(["AXRole", "AXChildren", "AXDOMClassList"]);
const LOOK = $(["AXRole", "AXDOMClassList", "AXValue", "AXEnabled"]);
const FOCUS = $(["AXRole", "AXChildren", "AXFocused"]);
const NO_AX = -25211, CANNOT = -25204;

const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
function put(text) {
  const data = $(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
  if (!data.isNil()) stdout.writeData(data);
}
function str(o) { try { return o.isKindOfClass($.NSString) ? o.js : ""; } catch (e) { return ""; } }
function yes(o) { try { return o.isKindOfClass($.NSNumber) && o.boolValue; } catch (e) { return false; } }
function hasClass(o) {
  try {
    if (!o.isKindOfClass($.NSArray)) return false;
    for (let i = 0; i < o.count; i++) {
      const c = str(o.objectAtIndex(i));
      if (c === CLASS || c.startsWith(CLASS + "__")) return true;
    }
  } catch (e) {}
  return false;
}

let visited = 0;
function copy(el, names) {                  // → NSArray of the values, or the Accessibility error code
  const v = Ref();
  const e = $.AXUIElementCopyMultipleAttributeValues(el, names, 0, v);
  return e === 0 ? ObjC.castRefToObject(v[0]) : e;
}
function value(el, name) {
  const v = Ref();
  const e = $.AXUIElementCopyAttributeValue(el, $(name), v);
  return e === 0 ? ObjC.castRefToObject(v[0]) : e;
}
function setFlag(el, name) { return $.AXUIElementSetAttributeValue(el, $(name), $.NSNumber.numberWithBool(true)); }
// A hung Discord answers every call after the timeout: 2 s for every element this process asks, not only the app's.
function appElement(pid) {
  const app = $.AXUIElementCreateApplication(pid);
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 2);
  $.AXUIElementSetMessagingTimeout(app, 2);
  setFlag(app, "AXManualAccessibility");
  return app;
}

// Walks the windows, depth first, for the two switches → { mute, deafen, window (the one they are in), error, windows,
// web }. Both must be in one window, in this order; a window with only one of them is passed over.
function find(app) {
  const result = { mute: null, deafen: null, window: null, error: 0, windows: 0, web: false };
  const wins = value(app, "AXWindows");
  if (typeof wins === "number") { result.error = wins; return result; }
  result.windows = Number(wins.count);
  for (let w = 0; w < wins.count; w++) {
    const found = [];
    const stack = [wins.objectAtIndex(w)];
    while (stack.length > 0 && found.length < 2) {
      const el = stack.pop();
      const a = copy(el, WALK);
      if (typeof a === "number") {
        if (a === NO_AX || a === CANNOT) { result.error = a; return result; }
        continue;
      }
      visited++;
      const role = str(a.objectAtIndex(0));
      if (role === "AXWebArea") result.web = true;
      if (role === "AXCheckBox" && hasClass(a.objectAtIndex(2))) { found.push(el); continue; }
      if (SKIP[role]) continue;
      const kids = a.objectAtIndex(1);
      if (kids.isKindOfClass($.NSArray)) for (let k = kids.count - 1; k >= 0; k--) stack.push(kids.objectAtIndex(k));
    }
    if (found.length === 2) {
      result.mute = found[0]; result.deafen = found[1]; result.window = wins.objectAtIndex(w);
      return result;
    }
  }
  return result;
}
// → { focused, web } of a window: the element with the keyboard focus, found outside lists, tables and trees only (the
// message list, the channel tree: the walk does not go there), and — when that is not found — the window's web area;
// each or null.
function focusedIn(win) {
  const result = { focused: null, web: null };
  const stack = [win];
  while (stack.length > 0) {
    const el = stack.pop();
    const a = copy(el, FOCUS);
    if (typeof a === "number") continue;
    visited++;
    const role = str(a.objectAtIndex(0));
    if (yes(a.objectAtIndex(2))) { result.focused = el; return result; }
    if (role === "AXWebArea" && !result.web) result.web = el;
    if (SKIP[role]) continue;
    const kids = a.objectAtIndex(1);
    if (kids.isKindOfClass($.NSArray)) for (let k = kids.count - 1; k >= 0; k--) stack.push(kids.objectAtIndex(k));
  }
  return result;
}
// Gives the focus back after a press, when the press took it to the switch.
function giveFocusBack(before, target) {
  const back = before.focused || before.web;
  if (!back || (before.focused && before.focused.isEqual(target))) return;
  if (yes(value(target, "AXFocused"))) setFlag(back, "AXFocused");
}
// Finds, and when a window shows no switches (Discord may build its web content only after being asked, and the web
// area may be there before what is in it), asks again and looks once more, half a second later.
function findExposed(app) {
  let r = find(app);
  if (r.error === 0 && !r.mute && r.windows > 0) {
    setFlag(app, "AXManualAccessibility");
    delay(0.5);
    r = find(app);
  }
  return r;
}
// → on (muted / deafened), off, unknown, or gone when the element is no longer one of the switches.
function stateOf(el) {
  if (!el) return "-";
  const a = copy(el, LOOK);
  if (typeof a === "number") return "gone";
  visited++;
  if (str(a.objectAtIndex(0)) !== "AXCheckBox" || !hasClass(a.objectAtIndex(1))) return "gone";
  const v = a.objectAtIndex(2);
  try {
    if (v.isKindOfClass($.NSNumber)) {
      const n = Number(v.intValue);
      if (n === 1) return "on";
      if (n === 0) return "off";
    }
  } catch (e) {}
  return "unknown";
}
function line(asked, discord, mute, deafen) { return asked + " " + discord + " " + mute + " " + deafen + " " + visited; }
function notFound(asked, r, cache) {
  if (r.error === NO_AX) return line(asked, "noax", "-", "-");
  if (r.error !== 0) return line(asked, "busy", "-", "-");   // quit or hung: the script sees which through lsappinfo
  cache.waited = r.windows > 0 && !r.web;
  return line(asked, cache.waited ? "wait" : r.windows > 0 ? "none" : "closed", "-", "-");
}

// One read. cache keeps { app, mute, deafen } between the reads of a long-lived reader; a single read gets a fresh {}.
// The first read of a reader, and every read after "wait", looks twice when it finds nothing.
function read(pid, cache) {
  const asked = Date.now();
  if (!cache.app) { cache.app = appElement(pid); cache.waited = true; }
  if (cache.mute) {                         // the switches found last time, while they are still the switches
    const mute = stateOf(cache.mute), deafen = stateOf(cache.deafen);
    if (mute !== "gone" && deafen !== "gone") return line(asked, "ok", mute, deafen);
    cache.mute = null; cache.deafen = null;
  }
  const r = cache.waited ? findExposed(cache.app) : find(cache.app);
  if (!r.mute) return notFound(asked, r, cache);
  cache.waited = false;
  cache.mute = r.mute; cache.deafen = r.deafen;
  return line(asked, "ok", stateOf(r.mute), stateOf(r.deafen));
}

function press(pid, which) {
  const r = findExposed(appElement(pid));
  if (r.error === NO_AX) return ["!noax"];
  if (r.error !== 0) return ["!busy"];
  if (r.windows === 0) return ["!closed"];
  if (!r.mute) return ["!none"];
  const target = which === "mute" ? r.mute : r.deafen;
  const enabled = value(target, "AXEnabled");
  if (typeof enabled !== "number" && !yes(enabled)) return ["!greyed"];
  const was = stateOf(target);
  const before = focusedIn(r.window);
  const e = $.AXUIElementPerformAction(target, $("AXPress"));
  if (e !== 0) return ["!press " + e];
  // Discord flips the switch once it has changed the state: the new state once it says on or off again, changed.
  // Not settled within 2 s: nothing is written, the next read tells.
  let now = was, asked = Date.now();
  for (let i = 0; i < 20 && !(now !== was && (now === "on" || now === "off")); i++) {
    delay(0.1);
    asked = Date.now();
    now = stateOf(target);
  }
  giveFocusBack(before, target);
  if (now === was || (now !== "on" && now !== "off")) return [""];
  let other = stateOf(which === "mute" ? r.deafen : r.mute);
  if (other === "gone") other = "-";
  return ["", asked + " ok " + (which === "mute" ? now + " " + other : other + " " + now) + " " + visited];
}

function run(argv) {
  const mode = argv[0], pid = Number(argv[1]);
  if (!(pid > 0)) { put("!no process id"); return; }
  if (mode === "read") { put(read(pid, {})); return; }
  if (mode === "press") {
    if (argv[2] !== "mute" && argv[2] !== "deafen") { put("!unknown switch " + argv[2]); return; }
    press(pid, argv[2]).forEach(put);
    return;
  }
  if (mode !== "loop") { put("!unknown mode " + mode); return; }
  const period = Number(argv[2]) || 1, idle = Number(argv[3]) || 5;
  const until = Date.now() + (Number(argv[4]) || 1800) * 1000;
  const cache = {};
  let recheck = 0;          // a walk can miss the panel once (Discord rebuilding it): "none" right after "ok" is looked
  while (Date.now() < until) {     // at again after 1 s, twice, before the idle pace (the script waits for 3 in a row)
    const text = read(pid, cache);
    put(text);
    const discord = text.split(" ")[1];
    if (discord === "noax") return;
    const quick = discord === "wait" || discord === "busy" || (discord === "none" && recheck-- > 0);
    if (discord === "ok") recheck = 2;
    delay(discord === "ok" ? period : quick ? 1 : idle);
  }
}
JS
  return 0
}
