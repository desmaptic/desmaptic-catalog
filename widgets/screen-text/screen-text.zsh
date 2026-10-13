# Text from Screen: the text in an area of the Mac's screen (tap), or in the picture already on the clipboard
# (hold), goes to the clipboard as plain text. Both commands are one line that names the mode, then this file
# (item.json):
#   "mode=select\n@file:screen-text.zsh"      — tap: select an area, as with ⌃⇧⌘4
#   "mode=clipboard\n@file:screen-text.zsh"   — hold: the picture already copied
#
# How the area is selected: the button presses the Mac's own "Copy picture of selected area to the clipboard"
# shortcut (⌃⇧⌘4, or whatever the user set for it in Keyboard Shortcuts › Screenshots) through System Events,
# as the built-in Screenshot Area action does — hence Accessibility and Automation. `screencapture -i -c` run
# by the agent would need neither, but it is not used: the tool is entitled to check Screen Recording on its
# responsible process (com.apple.private.tcc.check-allow-on-responsible-process), and that is the agent, which
# has no Screen Recording — macOS would ask for it, or hand over a picture of the wallpaper alone. The system
# shortcut takes the picture with the Screenshot app's own rights.
#
# The picture and the text never pass through the shell and never reach stdout, stderr or a log: osascript
# reads the clipboard through NSPasteboard, recognizes the text with Vision (the accurate level, the language
# found by macOS — every language it knows, none listed here) and QR codes with Core Image, writes the text
# back as plain text and answers with one word. (pbcopy would mangle every non-ASCII character here: it
# follows LC_ALL, which is C.) Lines go top to bottom; pieces on one line, left to right; a QR code becomes
# the text it encodes, in its place among the lines.
#
# Cancelled (Esc, or nothing selected for 50 s — the selection is then closed with Esc): the clipboard stays
# as it was, exit 0. Nothing recognized, no picture, a password: one line on stderr, exit 1 (the phone shakes
# the button). A screenshot with nothing in it is taken off the clipboard again and what was there before is
# put back, except a password (see `select`); whatever else reached the clipboard meanwhile — a copy by the
# user, Universal Clipboard — is left alone.
[[ $mode == (select|clipboard) ]] || { print -u2 -- "screen-text: unknown mode \"$mode\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# A named pasteboard instead of the Mac's clipboard: only the content tests set it, before this file.
# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
result=$(env -i /usr/bin/osascript -l JavaScript - $mode "${pasteboard-}" 2>/dev/null <<'JXA'
ObjC.import("AppKit");
ObjC.import("ApplicationServices");
ObjC.import("CoreGraphics");
ObjC.import("CoreImage");
ObjC.import("Vision");

// JXA hands NSInteger and NSUInteger over as strings ("0" === 0 is false, "12" + 4 is "124"): every count
// and change count is read through Number.

// What a password manager (or the New Password button) copies is marked so; the same marks as Translate's.
const marks = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
  "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping"];
// Pictures Core Image and Vision read, the most common first (a screenshot is PNG or TIFF).
const pictures = ["public.png", "public.tiff", "public.jpeg", "public.heic", "public.heif",
  "com.compuserve.gif", "org.webmproject.webp", "com.microsoft.bmp"];
// The selection waits this long, and the press must end within the agent's 60 s for it.
const selectionTime = 50;
// The selection's windows went away without a picture for this long: cancelled (Esc).
const cancelGrace = 3;
// The clipboard changed: the picture must be on it within this long, or the change was not the screenshot.
const pictureTime = 2;
// What the selection is shown by.
const captureApp = "com.apple.screencaptureui", captureTool = "/usr/sbin/screencapture";
// After a selection only these mean the screenshot itself gave nothing; any other refusal is about something
// else that reached the clipboard meanwhile.
const emptyShot = ["nothing", "unreadable", "unrecognized"];

function run(argv) {
  try {
    const board = argv[1] ? $.NSPasteboard.pasteboardWithName(argv[1]) : $.NSPasteboard.generalPasteboard;
    return argv[0] === "select" ? select(board) : recognize(board, Number(board.changeCount), true);
  } catch (error) {
    return "failed";
  }
}

// ---- tap: select an area ----

function select(board) {
  const shortcut = selectionShortcut();
  if (typeof shortcut === "string") return shortcut;
  if (!$.AXIsProcessTrusted()) return "accessibility";
  const before = Number(board.changeCount);
  // A password is not kept to be put back: written again, it would get a new change count, and a password
  // manager clears the clipboard only while the count is still the one it wrote — the password would stay
  // for good. The screenshot then stays in its place.
  const saved = holds(board, marks) ? null : snapshot(board);
  const earlier = captureWindows(null);
  const events = Application("System Events");
  try {
    events.keyCode(shortcut.code, { using: shortcut.modifiers });
  } catch (error) {
    if (error.errorNumber === -1743) return "automation";
    if (error.errorNumber === 1002) return "accessibility";
    return "unpressed";
  }
  const change = awaitPicture(board, before, earlier, events);
  if (change === null) return "cancelled";
  const result = recognize(board, change, false);
  // The screenshot gave nothing: it goes, what was copied before comes back — unless something else was
  // copied since.
  if (emptyShot.includes(result) && saved && Number(board.changeCount) === change) {
    board.clearContents;
    if (saved.length) board.writeObjects($(saved));
  }
  return result;
}

// The key of "Copy picture of selected area to the clipboard" (symbolic hotkey 31) as the user has it:
// { code, modifiers } for System Events, or a word when it is off. Key codes are positions, as WindowServer
// matches them, so no layout is consulted. No entry, or one without a key: the default, ⌃⇧⌘4; key 65535 —
// the user cleared the key, and ⌃⇧⌘4 may then mean something else.
function selectionShortcut() {
  const fallback = { code: 21, modifiers: ["command down", "shift down", "control down"] };
  const defaults = $.NSUserDefaults.alloc.initWithSuiteName("com.apple.symbolichotkeys");
  const hotkeys = ObjC.deepUnwrap(defaults.dictionaryForKey("AppleSymbolicHotKeys")) || {};
  const entry = hotkeys["31"];
  if (!entry) return fallback;
  if (!entry.enabled) return "shortcutoff";
  const parameters = entry.value && entry.value.parameters;
  if (!Array.isArray(parameters) || parameters.length < 3) return fallback;
  if (Number(parameters[1]) === 65535) return "shortcutoff";
  const flags = Number(parameters[2]);
  const names = [[1 << 17, "shift down"], [1 << 18, "control down"], [1 << 19, "option down"], [1 << 20, "command down"]];
  return { code: Number(parameters[1]), modifiers: names.filter(([bit]) => flags & bit).map(([, name]) => name) };
}

// Everything on the clipboard now, item by item and type by type, to put back when nothing is recognized;
// null when it is too big to keep (the screenshot then stays).
function snapshot(board) {
  const copies = [];
  let size = 0;
  for (const item of ObjC.unwrap(board.pasteboardItems) || []) {
    const copy = $.NSPasteboardItem.alloc.init;
    for (const type of ObjC.deepUnwrap(item.types) || []) {
      const data = item.dataForType(type);
      if (data.isNil()) continue;
      size += Number(data.length);
      if (size > 64 * 1024 * 1024) return null;
      copy.setDataForType(data, type);
    }
    copies.push(copy);
  }
  return copies;
}

// The numbers of the windows the screenshot UI shows now (its selection covers each display), except those in
// `earlier`. The owner is matched by its process — the screenshot UI's bundle id, or the screencapture tool's
// path — not by kCGWindowOwnerName, which is the app's localized name ("Screenshot", "Bildschirmfoto"…); the
// UI is launched on demand, so its process is looked up again on every call. Owners and numbers only — a
// window's title would need Screen Recording.
function captureWindows(earlier) {
  const owners = new Map();
  const isCapture = (pid) => {
    if (!owners.has(pid)) {
      const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid);
      const bundle = app.isNil() || app.bundleIdentifier.isNil() ? "" : app.bundleIdentifier.js;
      const path = app.isNil() || app.executableURL.isNil() ? "" : app.executableURL.path.js;
      owners.set(pid, bundle === captureApp || path === captureTool);
    }
    return owners.get(pid);
  };
  const list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1, 0));   // on screen only, all windows
  const numbers = [];
  for (let index = 0; index < Number(list.count); index++) {
    const window = list.objectAtIndex(index);
    if (!isCapture(Number(ObjC.unwrap(window.objectForKey("kCGWindowOwnerPID"))))) continue;
    const number = Number(ObjC.unwrap(window.objectForKey("kCGWindowNumber")));
    if (!earlier || !earlier.includes(number)) numbers.push(number);
  }
  return numbers;
}

// The clipboard's change count once the screenshot is on it, or null when the selection ended without one:
// its windows came and went (Esc), or none came within the time — then, if the selection is still on screen,
// it is closed with Esc, so it does not wait for a click the button no longer takes.
function awaitPicture(board, before, earlier, events) {
  const start = Date.now();
  let seen = false, lastSeen = 0, tick = 0;
  while (Date.now() - start < selectionTime * 1000) {
    delay(0.1);
    const change = Number(board.changeCount);
    if (change !== before) {
      // The count moves when the screenshot app clears the clipboard; the picture follows a moment later.
      // Nothing comes within the time: the change was something else (recognize then says so).
      const changed = Date.now();
      while (board.availableTypeFromArray($(pictures)).isNil() && Date.now() - changed < pictureTime * 1000) delay(0.05);
      return Number(board.changeCount);
    }
    if (tick++ % 3) continue;
    if (captureWindows(earlier).length) {
      seen = true;
      lastSeen = Date.now();
    } else if (seen && Date.now() - lastSeen > cancelGrace * 1000) {
      return null;
    }
  }
  // Only when its windows are certainly there: an Esc elsewhere would reach the app in front.
  if (Number(board.changeCount) === before && captureWindows(earlier).length) {
    try {
      events.keyCode(53);
    } catch (error) {
      // Left open: the user closes it with Esc.
    }
  }
  return null;
}

// ---- both: the picture on the clipboard to text ----

// Whether the clipboard, or any item on it, has one of the `wanted` types.
function holds(board, wanted) {
  const items = ObjC.unwrap(board.pasteboardItems) || [];
  const typeLists = [ObjC.deepUnwrap(board.types) || []].concat(items.map((item) => ObjC.deepUnwrap(item.types) || []));
  return typeLists.some((types) => types.some((type) => wanted.includes(type)));
}

// Recognizes the picture on the clipboard and puts the text in its place, if the clipboard is still at
// `change`; one word: "ok" or why not. `copied`: the picture was copied by the user, not taken by the selection.
function recognize(board, change, copied) {
  if (holds(board, marks)) return "concealed";
  if (!(ObjC.unwrap(board.pasteboardItems) || []).length) return "empty";
  // Files copied in Finder come with their icons as pictures: the icon's text is not what anyone wants.
  if (copied && holds(board, ["public.file-url"])) return "files";
  const type = board.availableTypeFromArray($(pictures));
  if (type.isNil()) return "nopicture";
  const data = board.dataForType(type);
  if (data.isNil()) return "nopicture";
  const image = $.CIImage.imageWithData(data);
  if (image.isNil()) return "unreadable";
  const extent = image.extent;
  const width = Number(extent.size.width), height = Number(extent.size.height);
  if (!(width > 0 && height > 0)) return "unreadable";

  // Pieces of text, each with its box in Vision's terms: 0…1 across the picture, y up from the bottom.
  const pieces = [];
  const detector = $.CIDetector.detectorOfTypeContextOptions($.CIDetectorTypeQRCode, $(),
    $.NSDictionary.dictionaryWithObjectForKey($.CIDetectorAccuracyHigh, $.CIDetectorAccuracy));
  const codes = detector.isNil() ? $() : detector.featuresInImage(image);
  const codeBoxes = [];
  for (let index = 0; index < (codes.isNil() ? 0 : Number(codes.count)); index++) {
    const code = codes.objectAtIndex(index);
    const message = code.messageString;
    if (message.isNil() || !Number(message.length)) continue;
    const bounds = code.bounds;
    const box = {
      x: (Number(bounds.origin.x) - Number(extent.origin.x)) / width,
      y: (Number(bounds.origin.y) - Number(extent.origin.y)) / height,
      width: Number(bounds.size.width) / width,
      height: Number(bounds.size.height) / height,
    };
    codeBoxes.push(box);
    pieces.push({ text: message, box });
  }

  const request = $.VNRecognizeTextRequest.alloc.init;
  request.recognitionLevel = 0;   // accurate: the fast level knows six Latin languages, Russian not among them
  request.usesLanguageCorrection = true;
  request.automaticallyDetectsLanguage = true;   // without it Chinese, Japanese and Arabic come out empty
  const handler = $.VNImageRequestHandler.alloc.initWithDataOptions(data, $.NSDictionary.dictionary);
  if (!handler.performRequestsError($.NSArray.arrayWithObject(request), $())) return "unrecognized";
  const observations = request.results;
  const inside = (box, area) => {
    const x = box.x + box.width / 2, y = box.y + box.height / 2;
    return x >= area.x && x <= area.x + area.width && y >= area.y && y <= area.y + area.height;
  };
  for (let index = 0; index < (observations.isNil() ? 0 : Number(observations.count)); index++) {
    const observation = observations.objectAtIndex(index);
    const candidate = observation.topCandidates(1).firstObject;
    if (candidate.isNil()) continue;
    const text = candidate.string.stringByTrimmingCharactersInSet($.NSCharacterSet.whitespaceAndNewlineCharacterSet);
    if (!Number(text.length)) continue;
    const frame = observation.boundingBox;
    const box = { x: Number(frame.origin.x), y: Number(frame.origin.y),
      width: Number(frame.size.width), height: Number(frame.size.height) };
    // What Vision reads inside a QR code is noise; the code itself is already there.
    if (codeBoxes.some((area) => inside(box, area))) continue;
    pieces.push({ text, box });
  }
  if (!pieces.length) return "nothing";

  // Top to bottom; a piece whose height mostly overlaps the line's first piece is on that line.
  pieces.sort((a, b) => (b.box.y + b.box.height) - (a.box.y + a.box.height));
  const lines = [];
  for (const piece of pieces) {
    const line = lines[lines.length - 1];
    const first = line && line[0].box;
    const overlap = first ? Math.min(first.y + first.height, piece.box.y + piece.box.height) - Math.max(first.y, piece.box.y) : 0;
    if (line && overlap > Math.min(first.height, piece.box.height) / 2) line.push(piece);
    else lines.push([piece]);
  }
  const result = $.NSMutableString.string;
  lines.forEach((line, row) => {
    line.sort((a, b) => a.box.x - b.box.x);
    line.forEach((piece, column) => {
      if (row || column) result.appendString(column ? " " : "\n");
      result.appendString(piece.text);
    });
  });

  // Something new was copied while this ran: it stays, the text goes nowhere.
  if (Number(board.changeCount) !== change) return "changed";
  board.clearContents;
  return board.setStringForType(result, "public.utf8-plain-text") ? "ok" : "unwritable";
}
JXA
)

case $result in
  ok|cancelled) exit 0 ;;
  empty)        print -u2 -- "screen-text: the clipboard is empty" ;;
  files)        print -u2 -- "screen-text: the clipboard holds files, not a picture" ;;
  nopicture)    print -u2 -- "screen-text: there is no picture on the clipboard" ;;
  concealed)    print -u2 -- "screen-text: the clipboard holds a password; it is left as it is" ;;
  unreadable)   print -u2 -- "screen-text: the picture on the clipboard cannot be read" ;;
  unrecognized) print -u2 -- "screen-text: macOS could not run text recognition" ;;
  nothing)      print -u2 -- "screen-text: no text or QR code in the picture" ;;
  changed)      print -u2 -- "screen-text: something new was copied meanwhile; it is left as it is" ;;
  unwritable)   print -u2 -- "screen-text: the clipboard refused the text" ;;
  shortcutoff)  print -u2 -- "screen-text: the shortcut \"Copy picture of selected area to the clipboard\" is off or has no key (System Settings > Keyboard > Keyboard Shortcuts > Screenshots)" ;;
  accessibility) print -u2 -- "screen-text: the agent needs Accessibility to start the selection (System Settings > Privacy & Security > Accessibility)" ;;
  automation)   print -u2 -- "screen-text: the agent may not control System Events (System Settings > Privacy & Security > Automation)" ;;
  unpressed)    print -u2 -- "screen-text: System Events did not press the screenshot shortcut" ;;
  *)            print -u2 -- "screen-text: osascript failed" ;;
esac
exit 1
