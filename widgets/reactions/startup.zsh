emojis="👍 👏 ❤️ 😂 🎉 🔥 😮 🚀"   # ← your emoji: change, add or remove them, with a space between each
# Reactions, the live loop (the button's startup script). A tap sends a burst of the emoji on the button floating up
# the Mac's screen; a long press steps to the next emoji of the line above. Edit that line to make the list your own:
# any emoji works — flags, skin tones, sequences such as ❤️‍🔥 — and so does a short word (GG, +1). Saving the button
# restarts this script with the new list; the emoji shown stays when the new list still has it.
#
# How it works. The tap and the long press only leave notes: an empty file per tap in $dir/taps and per long press in
# $dir/next. This loop owns the list: it keeps the emoji now in $dir/emoji and draws the button's face — the emoji
# big, a dot per emoji of the list with the current one lit. A tap starts the overlay: one osascript (JXA) process
# that draws the bursts over the screens (see its own notes below). The overlay reads the taps itself, a dozen times
# a second, so while it runs a tap shows at once; it stays up keep_alive seconds after the last burst and then quits,
# and the next tap starts it again (about half a second). It also quits when this loop is gone, even killed, and this
# loop ends it on TERM, INT and HUP: the agent stops startup scripts when the phone disconnects and when it quits.
# While the overlay is down this loop looks at the two folders four times a second (builtin globs, no process).
#
# The face is posted at the start, after a long press (the new emoji pops in), after every burst (a small copy flies
# off the face) and every keyframe seconds, as one request that runs beside this loop (a slow agent never holds it up).
#
# Tool modes, no network and no window: --face <rest|demo> <out.svg> writes the Gallery faces (rest.svg, demo.svg);
# --preview <out.png> draws one burst at six moments and every emoji of the list into one picture, and the same
# burst as Core Animation draws its layers 1.2 s in into <out>-layers.png. Any other argument prints the usage.
# REACTIONS_DRY=1 runs the loop but prints the frames instead of posting them and the bursts instead of drawing them;
# REACTIONS_DRY=2 prints the frames and draws the bursts for real (on screen: for a check with someone watching).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/system || { print -u2 -- "reactions: zsh modules datetime/zselect/system are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "reactions: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
taps="$dir/taps"                # the tap: an empty file per tap, named by its time. The overlay takes them
nexts="$dir/next"               # the long press: an empty file per press. This loop takes them
word_file="$dir/emoji"          # this loop: the emoji now (the overlay draws it; kept across restarts)
pid_file="$dir/loop"            # this loop: its pid, so a tap knows something will draw it
keep_alive=180                  # s the overlay stays up after the last burst, so the next tap shows at once
keyframe=30                     # s: the face is posted again (something outside may have reset it)
dry=${REACTIONS_DRY:-0}
[[ $dry == [012] ]] || dry=0

list=( ${=emojis} )             # the words of the first line
(( $#list )) || list=( 👍 )

overlay_js='ObjC.import("AppKit");
ObjC.import("QuartzCore");
ObjC.bindFunction("getppid", ["int", []]);

// Reactions over the screen of the Mac: one see-through window per display, above everything (full screen apps too, every
// Space), clicks pass through, never focused, no Dock icon, and on screen only while copies fly. A burst is a handful
// of plain layers that share one bitmap of the emoji, drawn once by AppKit (so any emoji works: flags, skin tones,
// sequences such as the heart on fire), each with one animation the window server plays at the rate of the display;
// this process only reads the folder of taps a dozen times a second.
//
// argv: <dir> <seconds>. <dir>/taps holds one empty file per tap, named by its time ("1727780000.123456.512"): each
// becomes a burst of the word in <dir>/emoji and is removed. Prints "up" once, "burst" for every burst, "." every
// second and "bye" when it quits by itself: <seconds> after the last burst, once its copies have flown. Quits at once
// when the loop that started it is gone (its parent changes).
// Tool mode, no window: --preview <out.png> <word>... draws a burst of the first word at six moments and the bitmap of
// every word into one picture, and builds the layers and animations of one burst off screen.

const FRESH = 6;            // s: an older tap is dropped (the loop was busy starting this process, the Mac slept)
const COPIES = 7;           // copies of the emoji in one burst
const MOST = 60;            // at most this many copies in the air together; a tap beyond that is dropped
const LIFE = 2.3;           // s: each copy flies LIFE...LIFE + LIFE_SPREAD
const LIFE_SPREAD = 0.6;
const STAGGER = 0.45;       // s: the copies of a burst set off over this long
const POP = 0.14;           // share of the life a copy takes to pop up from half its size
const SAMPLES = 40;         // points of the path of each copy handed to Core Animation (denser at the start: the pop)
const POLL = 1 / 12;        // s: how often the folder of taps is read

const out = $.NSFileHandle.fileHandleWithStandardOutput;
const err = $.NSFileHandle.fileHandleWithStandardError;
function say(text) { out.writeData($(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function complain(text) { err.writeData($("reactions: " + text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function number(x) { return $.NSNumber.numberWithDouble(x); }

// Park-Miller: the preview draws the same burst every time; live bursts take Math.random.
function seeded(seed) {
  let s = seed % 2147483647;
  if (s <= 0) s += 2147483646;
  return () => (s = s * 16807 % 2147483647) / 2147483647;
}

// The size of one copy on a display H pt high: about a thirteenth of it.
function sizeFor(H) { return Math.round(Math.min(100, Math.max(48, H * 0.075))); }

// One burst on a display of W x H pt (y up, 0 at the bottom) with the pointer at x = px: the numbers of every copy.
// The copies leave the bottom edge across a band centred under the pointer, each from its own slot, in shuffled order.
function plan(rand, W, H, px, pt) {
  const band = Math.max(0, Math.min(W - 2 * pt, Math.max(5 * pt, W * 0.18)));
  const cx = Math.min(W - pt - band / 2, Math.max(pt + band / 2, px));
  const slots = [];
  for (let i = 0; i < COPIES; i++) slots.push(i);
  for (let i = COPIES - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)), s = slots[i]; slots[i] = slots[j]; slots[j] = s; }
  const list = [];
  for (let i = 0; i < COPIES; i++) {
    list.push({
      delay: (i + 0.8 * rand()) * STAGGER / COPIES,
      life: LIFE + rand() * LIFE_SPREAD,
      x: cx + ((slots[i] + 0.2 + 0.6 * rand()) / COPIES - 0.5) * band,
      y: pt * 0.3,
      rise: H * (0.42 + 0.26 * rand()),
      sway: (rand() < 0.5 ? -1 : 1) * pt * (0.12 + 0.22 * rand()),
      turns: 0.55 + 0.6 * rand(),              // sways over the flight
      phase: rand() * 2 * Math.PI,
      scale: 0.75 + 0.45 * rand(),
    });
  }
  return list;
}

// Where copy c is at u (0...1 of its flight): its centre (pt), scale, opacity and lean (rad, positive = to the left).
// It pops up from half its size, rises fast and slows a little, sways side to side leaning into the swing, grows a
// little and fades out over the last part of the flight.
function at(c, u) {
  const climb = 0.6 * u * (2 - u) + 0.4 * u;
  const b = Math.min(1, u / POP) - 1, pop = 1 + 2.70158 * b * b * b + 1.70158 * b * b;
  const w = 2 * Math.PI * c.turns * u + c.phase;
  const fade = u < 0.08 ? u / 0.08 : u < 0.55 ? 1 : Math.max(0, 1 - Math.pow((u - 0.55) / 0.45, 1.5));
  return {
    x: c.x + c.sway * (Math.sin(w) - Math.sin(c.phase)),
    y: c.y + c.rise * climb,
    s: c.scale * (0.5 + 0.5 * pop) * (1 + 0.22 * u),
    a: fade,
    r: -0.13 * Math.cos(w) * Math.sign(c.sway),
  };
}

const KEY_TIMES = [];
for (let k = 0; k <= SAMPLES; k++) KEY_TIMES.push(Math.pow(k / SAMPLES, 1.4));
const KEY_TIMES_NS = $(KEY_TIMES.map(number));

// The bitmap of a word: AppKit draws it in the system font (emoji come from the emoji font by themselves), white, with
// a soft shadow that shows it on white windows too. pt: the font size; scale: pixels per point. The NSImage is an
// ordinary object, freed with its last user: nothing here needs CFRelease, which crashes from JXA.
function wordImage(text, pt, scale) {
  const font = $.NSFont.systemFontOfSizeWeight(pt, 0.3);
  const shadow = $.NSShadow.alloc.init;
  shadow.setShadowOffset($.CGSizeMake(0, -pt * 0.03));
  shadow.setShadowBlurRadius(pt * 0.09);
  shadow.setShadowColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0, 0, 0, 0.35));
  const attrs = $.NSMutableDictionary.dictionary;
  attrs.setObjectForKey(font, $.NSFontAttributeName);
  attrs.setObjectForKey($.NSColor.whiteColor, $.NSForegroundColorAttributeName);
  attrs.setObjectForKey(shadow, $.NSShadowAttributeName);
  const str = $(text);
  const box = str.sizeWithAttributes(attrs), pad = Math.ceil(pt * 0.22);
  const w = Math.ceil(box.width) + 2 * pad, h = Math.ceil(box.height) + 2 * pad;
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, Math.ceil(w * scale), Math.ceil(h * scale), 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
  rep.setSize($.CGSizeMake(w, h));
  const g = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext(g);
  str.drawAtPointWithAttributes($.CGPointMake(pad, pad), attrs);
  g.flushGraphics;
  $.NSGraphicsContext.restoreGraphicsState;
  const image = $.NSImage.alloc.initWithSize($.CGSizeMake(w, h));
  image.addRepresentation(rep);
  return { image: image, rep: rep, w: w, h: h, scale: scale };
}

function keyframes(path, values) {
  const a = $.CAKeyframeAnimation.animationWithKeyPath(path);
  a.setValues($(values.map(number)));
  a.setKeyTimes(KEY_TIMES_NS);
  return a;
}

// The layers of one burst, added to root: each copy waits for its delay (hidden), flies, and stays hidden after.
// begin: the time of the root now. Returns the layers with the time (of clock()) each one has finished.
function launch(root, img, copies, begin, now, contentsScale) {
  const flying = [];
  for (const c of copies) {
    const xs = [], ys = [], ss = [], as = [], rs = [];
    for (const u of KEY_TIMES) { const p = at(c, u); xs.push(p.x); ys.push(p.y); ss.push(p.s); as.push(p.a); rs.push(p.r); }
    const layer = $.CALayer.layer;
    layer.setContents(img.image);
    layer.setContentsScale(contentsScale);
    layer.setBounds($.CGRectMake(0, 0, img.w, img.h));
    layer.setPosition($.CGPointMake(xs[xs.length - 1], ys[ys.length - 1]));
    layer.setOpacity(0);
    const parts = [keyframes("position.x", xs), keyframes("position.y", ys), keyframes("transform.scale", ss),
                   keyframes("opacity", as), keyframes("transform.rotation.z", rs)];
    for (const p of parts) p.setDuration(c.life);
    const fly = $.CAAnimationGroup.animation;
    fly.setAnimations($(parts));
    fly.setDuration(c.life);
    fly.setBeginTime(begin + c.delay);
    fly.setFillMode($.kCAFillModeBackwards);
    layer.addAnimationForKey(fly, "fly");
    root.addSublayer(layer);
    flying.push({ layer: layer, ends: now + c.delay + c.life + 0.1 });
  }
  return flying;
}

// --- Tool mode: a picture of one burst, no window ---------------------------------------------------------------

function preview(args) {
  const file = args[0] || "", words = args.slice(1);
  if (!file || !words.length) { complain("usage: --preview <out.png> <word>..."); return; }
  const W = 1440, H = 900, k = 0.4, gap = 12, pt = sizeFor(H), px = 1000;
  const img = wordImage(words[0], pt, 2), copies = plan(seeded(20261001), W, H, px, pt);
  const moments = [0.15, 0.45, 0.9, 1.4, 2.0, 2.6];
  const pw = W * k, ph = H * k, strip = 150;
  const cw = Math.ceil(3 * pw + 4 * gap), ch = Math.ceil(2 * ph + 3 * gap + strip);
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, cw * 2, ch * 2, 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
  rep.setSize($.CGSizeMake(cw, ch));
  const g = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext(g);
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.08, 0.08, 0.09, 1).setFill;
  $.NSBezierPath.fillRect($.CGRectMake(0, 0, cw, ch));
  const label = $.NSMutableDictionary.dictionary;
  label.setObjectForKey($.NSFont.monospacedDigitSystemFontOfSizeWeight(14, 0), $.NSFontAttributeName);
  label.setObjectForKey($.NSColor.colorWithSRGBRedGreenBlueAlpha(0, 0, 0, 0.6), $.NSForegroundColorAttributeName);
  moments.forEach((t, i) => {
    const ox = gap + (i % 3) * (pw + gap), oy = strip + gap + (1 - Math.floor(i / 3)) * (ph + gap);
    // A light desktop with a dark window on it: the copies must read on both.
    $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.93, 0.93, 0.95, 1).setFill;
    $.NSBezierPath.fillRect($.CGRectMake(ox, oy, pw, ph));
    $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.16, 0.17, 0.2, 1).setFill;
    $.NSBezierPath.fillRect($.CGRectMake(ox + pw * 0.08, oy + ph * 0.12, pw * 0.5, ph * 0.7));
    $.NSColor.colorWithSRGBRedGreenBlueAlpha(1, 0.2, 0.3, 1).setFill;            // the pointer
    $.NSBezierPath.fillRect($.CGRectMake(ox + px * k - 3, oy + ph * 0.5 - 3, 6, 6));
    for (const c of copies) {
      const u = (t - c.delay) / c.life;
      if (u < 0 || u > 1) continue;
      const p = at(c, u);
      $.NSGraphicsContext.saveGraphicsState;
      const xf = $.NSAffineTransform.transform;
      xf.translateXByYBy(ox + p.x * k, oy + p.y * k);
      xf.rotateByRadians(p.r);
      xf.scaleBy(p.s * k);
      xf.concat;
      img.image.drawInRectFromRectOperationFraction($.CGRectMake(-img.w / 2, -img.h / 2, img.w, img.h),
        $.CGRectMake(0, 0, 0, 0), 2, p.a);
      $.NSGraphicsContext.restoreGraphicsState;
    }
    $(t.toFixed(2) + " s").drawAtPointWithAttributes($.CGPointMake(ox + 6, oy + ph - 22), label);
  });
  // The bitmap of every word at the size a 900 pt display gets, side by side.
  let x = gap;
  for (const word of words) {
    const one = wordImage(word, pt, 2);
    const s = Math.min(1, 130 / one.h);
    one.image.drawInRectFromRectOperationFraction($.CGRectMake(x, 10, one.w * s, one.h * s), $.CGRectMake(0, 0, 0, 0), 2, 1);
    x += one.w * s + 4;
  }
  g.flushGraphics;
  $.NSGraphicsContext.restoreGraphicsState;
  const png = rep.representationUsingTypeProperties(4, $.NSDictionary.dictionary);    // 4: PNG
  if (!png.writeToFileAtomically($(file), true)) { complain("cannot write " + file); return; }
  // The live path, off screen: the layers and animations on a root no window shows.
  const root = $.CALayer.layer;
  root.setFrame($.CGRectMake(0, 0, W, H));
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  const flying = launch(root, img, copies, $.CACurrentMediaTime(), 0, 2);
  $.CATransaction.commit;
  let animations = 0;
  for (const f of flying) {
    const fly = f.layer.animationForKey("fly");
    if (!fly.isNil()) animations += Number(fly.animations.count);
  }
  // Those very layers drawn by Core Animation into a bitmap (<out>-layers.png), each set through the key paths its
  // animation plays to where it is 1.2 s into the burst: what the window would show at that moment.
  const lw = W / 2, lh = H / 2;
  const lrep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, lw, lh, 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
  const lg = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(lrep), lctx = lg.CGContext;
  $.CGContextSetRGBFillColor(lctx, 0.93, 0.93, 0.95, 1);
  $.CGContextFillRect(lctx, $.CGRectMake(0, 0, lw, lh));
  $.CGContextScaleCTM(lctx, 0.5, 0.5);
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  copies.forEach((c, i) => {
    const p = at(c, Math.min(1, Math.max(0, (1.2 - c.delay) / c.life))), layer = flying[i].layer;
    layer.removeAllAnimations;
    for (const [path, v] of [["position.x", p.x], ["position.y", p.y], ["transform.scale", p.s], ["opacity", p.a], ["transform.rotation.z", p.r]])
      layer.setValueForKeyPath(number(v), path);
  });
  $.CATransaction.commit;
  root.renderInContext(lctx);
  lg.flushGraphics;
  const lpng = lrep.representationUsingTypeProperties(4, $.NSDictionary.dictionary);
  const layersFile = file.replace(/\.png$/, "") + "-layers.png";
  if (!lpng.writeToFileAtomically($(layersFile), true)) { complain("cannot write " + layersFile); return; }
  say("preview: " + file + ", " + Number(root.sublayers.count) + " layers, " + animations + " animations, " +
      KEY_TIMES.length + " points each, bitmap " + img.w + "x" + img.h + " pt; " + layersFile);
}

// --- Live ----------------------------------------------------------------------------------------------------------

// The display under the pointer, its key ("x y w h scale": a window per key) and the x of the pointer on it.
function pointerDisplay() {
  const p = $.NSEvent.mouseLocation, screens = $.NSScreen.screens, n = Number(screens.count);
  let pick = null;
  for (let i = 0; i < n && !pick; i++) {
    const s = screens.objectAtIndex(i), f = s.frame;
    if (p.x >= f.origin.x && p.x <= f.origin.x + f.size.width && p.y >= f.origin.y && p.y <= f.origin.y + f.size.height) pick = s;
  }
  if (!pick && n) pick = screens.objectAtIndex(0);
  if (!pick) return null;
  const f = pick.frame;
  return { screen: pick, frame: f, scale: Number(pick.backingScaleFactor), px: p.x - f.origin.x,
           key: [f.origin.x, f.origin.y, f.size.width, f.size.height, pick.backingScaleFactor].join(" ") };
}

function displayKeys() {
  const screens = $.NSScreen.screens, keys = [];
  for (let i = 0; i < Number(screens.count); i++) {
    const s = screens.objectAtIndex(i), f = s.frame;
    keys.push([f.origin.x, f.origin.y, f.size.width, f.size.height, s.backingScaleFactor].join(" "));
  }
  return keys;
}

function makeWindow(d) {
  const w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(d.frame, 0, 2, false);   // borderless, buffered
  w.setOpaque(false);
  w.setBackgroundColor($.NSColor.clearColor);
  w.setHasShadow(false);
  w.setIgnoresMouseEvents(true);
  w.setReleasedWhenClosed(false);
  w.setLevel(1000);                                         // the screen saver level
  w.setCollectionBehavior(1 | 16 | 64 | 256);               // all Spaces, stationary, out of the window cycle, full screen
  const view = w.contentView;
  view.setWantsLayer(true);
  const root = $.CALayer.layer;
  root.setFrame($.CGRectMake(0, 0, d.frame.size.width, d.frame.size.height));
  view.layer.addSublayer(root);
  return { window: w, root: root, flying: [], scale: d.scale, shown: false };
}

// AppKit learns about added and removed displays from events: take the waiting ones without blocking.
function takeEvents() {
  const app = $.NSApplication.sharedApplication;
  for (let i = 0; i < 64; i++) {
    const e = app.nextEventMatchingMaskUntilDateInModeDequeue($.NSEventMaskAny, $.NSDate.distantPast, $.NSDefaultRunLoopMode, true);
    if (e.isNil()) break;
  }
}

function transaction(work) {
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  try { work(); } finally { $.CATransaction.commit; $.CATransaction.flush; }
}

function run(argv) {
  if (argv[0] === "--preview") return preview(argv.slice(1));
  const dir = argv[0] || "", rest = Number(argv[1]) || 180;
  if (!dir) { complain("usage: <dir> <seconds> | --preview <out.png> <word>..."); return; }
  const files = $.NSFileManager.defaultManager, parent = $.getppid();
  const taps = $(dir + "/taps"), wordFile = $(dir + "/emoji");
  const info = $.NSProcessInfo.processInfo, up0 = info.systemUptime, clock = () => info.systemUptime - up0;
  $.NSApplication.sharedApplication.setActivationPolicy(1);   // accessory: no Dock icon, never active
  const shows = new Map(), images = new Map();
  let lastBurst = 0, beat = 0, inAir = 0;
  say("up");
  for (;;) {
    const t = clock();
    if ($.getppid() !== parent) { transaction(() => { for (const s of shows.values()) s.window.orderOut(null); }); return; }
    const names = files.contentsOfDirectoryAtPathError(taps, null);
    const n = names.isNil() ? 0 : Number(names.count);
    if (n > 0) {
      const wall = Date.now() / 1000;
      let fresh = 0;
      for (let i = 0; i < n; i++) {
        const name = ObjC.unwrap(names.objectAtIndex(i));
        files.removeItemAtPathError($(dir + "/taps/" + name), null);
        const when = parseFloat(name);
        if (when > wall - FRESH && when < wall + 2) fresh++;
      }
      for (let b = 0; b < Math.min(fresh, 3) && inAir + COPIES <= MOST; b++) {
        try {
          takeEvents();
          const d = pointerDisplay();
          if (!d) { complain("no display"); break; }
          const keys = displayKeys();
          for (const [key, s] of shows) {                      // a display that went away: its window goes too
            if (keys.indexOf(key) < 0) { transaction(() => s.window.orderOut(null)); inAir -= s.flying.length; shows.delete(key); }
          }
          let show = shows.get(d.key);
          if (!show) { show = makeWindow(d); shows.set(d.key, show); }
          const H = d.frame.size.height, pt = sizeFor(H);
          let word = $.NSString.stringWithContentsOfFileEncodingError(wordFile, $.NSUTF8StringEncoding, null);
          word = word.isNil() ? "" : word.js.trim();
          if (!word) word = "\u{1F44D}";
          const scale = Math.ceil(d.scale * 1.3), id = word + "|" + pt + "|" + scale;
          let img = images.get(id);
          if (!img) {
            img = wordImage(word, pt, scale);
            images.set(id, img);
            if (images.size > 4) images.delete(images.keys().next().value);
          }
          const copies = plan(Math.random, d.frame.size.width, H, d.px, pt);
          transaction(() => {
            const flying = launch(show.root, img, copies, $.CACurrentMediaTime(), clock(), d.scale);
            show.flying = show.flying.concat(flying);
            inAir += flying.length;
            if (!show.shown) { show.window.orderFrontRegardless; show.shown = true; }
          });
          lastBurst = clock();
          say("burst");
        } catch (e) { complain("no burst: " + e); }
      }
    }
    // Copies that have flown go; a window with none left leaves the screen.
    const now = clock();
    for (const s of shows.values()) {
      if (!s.flying.some(f => f.ends <= now)) continue;
      transaction(() => {
        const keep = [];
        for (const f of s.flying) { if (f.ends <= now) f.layer.removeFromSuperlayer; else keep.push(f); }
        inAir -= s.flying.length - keep.length;
        s.flying = keep;
        if (!keep.length && s.shown) { s.window.orderOut(null); s.shown = false; }
      });
    }
    if (now >= beat) { beat = now + 1; say("."); }
    if (inAir <= 0 && now - lastBurst > rest) { transaction(() => { for (const s of shows.values()) s.window.orderOut(null); }); say("bye"); return; }
    delay(POLL);
  }
}'

# size_for <word>: REPLY = its font size on the face: 100 for an emoji, less for a word of several letters. (Under
# LC_ALL=C a length counts bytes: an emoji is told by its bytes, a word by its letters' first bytes.)
size_for() {
  local w=$1 letters
  if [[ $w == *[$'\xf0'-$'\xf4']* || $w == *$'\xef\xb8\x8f'* || $w == *$'\xe2\x80\x8d'* ]]; then REPLY=100; return; fi
  letters=${w//[$'\x80'-$'\xbf']/}
  case ${#letters} in
    (1) REPLY=100 ;; (2) REPLY=84 ;; (3) REPLY=64 ;; (4) REPLY=50 ;; (5) REPLY=40 ;; (*) REPLY=32 ;;
  esac
}

# face <word> <lit dot, from 0> <dots> <rest|launch|pop|demo>: REPLY = one frame of the face (SVG, 200 x 200). Every
# phase has the same elements, so the phone glides from one to the next: a soft glow in the button's colour, a dot
# for each emoji of the list (one dashed line) with the lit dot over the current one, the emoji, and a copy of it
# that flies off up and to the right after a burst.
#   rest    the emoji; the copy waits where it flies to, invisible
#   launch  the copy over the emoji, the emoji pressed in a little (posted at once; rest then glides the copy off)
#   pop     the emoji small and faint (a new one: rest then grows it)
#   demo    the Gallery picture: the copy on its way off
face() {
  local word=$1 phase=$4
  local -F lit=$2 n=$3 gap w x1 x2 dx r dots=0.3 shine=1 size fs op=1 ey=88 gx=100 gy=88 gfs ga=0
  size_for $word; size=$REPLY
  word=${word//&/&amp;} word=${word//</&lt;} word=${word//>/&gt;}
  if (( n >= 2 )); then
    (( gap = 120 / (n - 1) )); (( gap > 18 )) && gap=18
    (( w = gap * 0.4 )); (( w > 6.5 )) && w=6.5
  else
    n=1 gap=18 w=6.5 dots=0 shine=0
  fi
  (( x1 = 100 - (n - 1) * gap / 2, x2 = x1 + (n - 1) * gap + 0.01, dx = x1 + lit * gap, r = w * 0.8 ))
  fs=$size gfs=$size
  case $phase in
    (rest)   gx=150 gy=16 gfs=$(( size * 0.5 )) ;;
    (launch) fs=$(( size * 0.88 )) ga=0.9 ;;
    (pop)    fs=$(( size * 0.4 )) op=0.15 gx=150 gy=16 gfs=$(( size * 0.5 )) ;;
    (demo)   gx=150 gy=34 gfs=$(( size * 0.5 )) ga=0.8 ;;
  esac
  printf -v REPLY '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><defs><radialGradient id="glowG"><stop offset="0" stop-color="currentColor" stop-opacity="0.30"/><stop offset="1" stop-color="currentColor" stop-opacity="0"/></radialGradient></defs><circle id="glow" cx="100" cy="88" r="80" fill="url(#glowG)"/><line id="dots" x1="%.2f" y1="168" x2="%.2f" y2="168" stroke="#FFFFFF" stroke-opacity="%.2f" stroke-width="%.2f" stroke-linecap="round" stroke-dasharray="0 %.2f"/><circle id="dot" cx="%.2f" cy="168" r="%.2f" fill="#FFFFFF" fill-opacity="%.2f"/><text id="emoji" x="100" y="%.2f" font-size="%.2f" font-weight="700" opacity="%.2f" fill="#FFFFFF" text-anchor="middle" dominant-baseline="middle">%s</text><text id="ghost" x="%.2f" y="%.2f" font-size="%.2f" font-weight="700" opacity="%.2f" fill="#FFFFFF" text-anchor="middle" dominant-baseline="middle">%s</text></svg>' \
    $x1 $x2 $dots $w $gap $dx $r $shine $ey $fs $op $word $gx $gy $gfs $ga $word
}

usage() { print -u2 -- "usage: startup.zsh [--face <rest|demo> <out.svg> | --preview <out.png>]"; exit 2 }
if (( $# )); then
  case $1 in
    (--face)
      (( $# == 3 )) && [[ $2 == (rest|demo) ]] || usage
      if [[ $2 == rest ]]; then face $list[1] 0 $#list rest
      else (( d = $#list < 5 ? $#list : 5 )); face $list[d] $(( d - 1 )) $#list demo; fi
      { print -rn -- $REPLY > $3 } 2>/dev/null || { print -u2 -- "reactions: cannot write $3"; exit 1 }
      exit 0 ;;
    (--preview)
      (( $# == 2 )) || usage
      exec osascript -l JavaScript -e "$overlay_js" -- --preview $2 $list ;;
    (*) usage ;;
  esac
fi
if (( dry == 0 )) && [[ -z ${DESMAPTIC_TOKEN:-} ]]; then
  print -u2 -- "reactions: not started by Desmaptic Agent (no DESMAPTIC_TOKEN): try REACTIONS_DRY=1"
  exit 1
fi

opid=""                 # the overlay
post_fd=0 post_pid=0    # a post on its way: the pipe its answer comes back on, and its process
# stop_overlay [signal]: ends the overlay (TERM; KILL for one that does not answer). Its windows go with it.
stop_overlay() { [[ -n $opid ]] && kill -${1:-TERM} $opid 2>/dev/null; opid="" }
# drop_post: forgets a post on its way and ends it.
drop_post() { (( post_pid )) && kill $post_pid 2>/dev/null; (( post_fd )) && exec {post_fd}<&-; post_fd=0 post_pid=0 }
# forget_pid: the pid file goes, unless a newer loop has already written its own.
forget_pid() { local p=""; { IFS= read -r p < $pid_file } 2>/dev/null; [[ $p == $$ ]] && zf_rm -f -- $pid_file 2>/dev/null }
trap 'stop_overlay; drop_post; forget_pid; exit 0' TERM INT HUP
trap 'stop_overlay; drop_post' EXIT

# keep_word: $dir/emoji = the emoji now, replaced in one step (the overlay never reads half of it).
keep_word() {
  { print -rn -- $list[idx] > $word_file.$$ } 2>/dev/null && zf_mv -f -- $word_file.$$ $word_file 2>/dev/null ||
    { zf_rm -f -- $word_file.$$ 2>/dev/null; print -u2 -- "reactions: cannot write in $dir"; return 1 }
}

# The overlay, as a coprocess: its lines ("up", "burst", a "." every second, "bye") come back to this loop.
start_overlay() {
  coproc osascript -l JavaScript -e "$overlay_js" -- $dir $keep_alive
  opid=$! began=$EPOCHSECONDS heard=$EPOCHREALTIME said_bye=0
}

# body <svg> <duration>: REPLY = the request that puts one frame on the button.
body() {
  local s=$1
  s=${s//\\/\\\\} s=${s//\"/\\\"}
  REPLY="{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$s\",\"duration\":$2,\"easing\":\"easeInOut\"}}"
}

# show <rest|burst|pop>: posts what the face does now, one request per frame, in order, without waiting for the
# answer. rest: the face as it is; burst: a copy flies off; pop: the new emoji grows in while the lit dot moves
# from the one before (from). The process runs beside this loop (first its pid, then a status line per frame
# come back on post_fd); post_check reads it. The token goes from the environment into the request by the
# process itself, never on a command line.
show() {
  local -a bodies args
  local b lit=$(( idx - 1 )) glide=0.35
  case $1 in
    (burst) face $list[idx] $lit $#list launch; body $REPLY 0; bodies+=($REPLY) ;;
    (pop)   face $list[idx] $(( from - 1 )) $#list pop; body $REPLY 0; bodies+=($REPLY) ;;
  esac
  face $list[idx] $lit $#list rest
  [[ $1 == burst ]] && glide=0.7
  body $REPLY $glide
  bodies+=($REPLY)
  posted_at=$EPOCHSECONDS
  if (( dry )); then
    for b in $bodies; do print -r -- "frame: $b"; done
    return 0
  fi
  for b in $bodies; do
    (( $#args )) && args+=(--next)
    args+=(-sS --max-time 3 -o /dev/null -w '%{http_code}\n'
      --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}'
      -H 'Content-Type: application/json' --data-binary $b http://127.0.0.1:9848/api/update-button)
  done
  exec {post_fd}< <(print -r -- $sysparams[pid]; exec curl -q $args 2>&1) || { post_fd=0; return 1 }
  post_pid=0 answer=""
  { IFS= read -r -t 1 -u $post_fd post_pid } 2>/dev/null
  [[ $post_pid == <-> ]] || post_pid=0
}

# post_check: never waits — it takes only the bytes already there (sysread, not a line read that would wait for
# the rest of a line). Once the whole answer is in: every frame taken is 200 on its own line; otherwise the failure
# is reported once and the face is posted again in 2 s.
post_check() {
  local chunk left
  while zselect -t 0 -r $post_fd; do
    if sysread -i $post_fd chunk 2>/dev/null; then answer+=$chunk; continue; fi
    exec {post_fd}<&-                               # the end (or a broken pipe): the post is over
    post_fd=0 post_pid=0
    left=${answer//200/} left=${left//$'\n'/}
    if [[ -n $answer && -z $left ]]; then failing=0
    else
      (( failing )) || print -u2 -- "reactions: update-button did not take the face: ${${answer//$'\n'/ }[1,200]}"
      failing=1 retry_at=$(( EPOCHSECONDS + 2 ))
      [[ -n $pending ]] || pending=rest
    fi
    return
  done
}

zf_mkdir -p -- $taps $nexts 2>/dev/null
[[ -d $taps && -d $nexts ]] || { print -u2 -- "reactions: cannot write in $dir"; exit 1 }
stale=( $taps/*(N) $nexts/*(N) )        # left from before this loop: too late to show
(( $#stale )) && zf_rm -f -- $stale
# The emoji now: the one kept from the last run while the list still has it, otherwise the first.
idx=1 kept=""
{ IFS= read -r kept < $word_file } 2>/dev/null
for (( i = 1; i <= $#list; i++ )); do [[ $list[i] == "$kept" ]] && { idx=$i; break }; done
keep_word || exit 1
{ print -r -- $$ > $pid_file } 2>/dev/null || { print -u2 -- "reactions: cannot write in $dir"; exit 1 }

waits=(5 10 20 40 60)   # after the overlay failed: seconds before the next try
fails=0 start_at=0      # the overlay failed so many times in a row; when to try again
pending=rest            # what the face does next: rest, burst, pop; "" nothing
from=$idx               # pop: the emoji before
posted_at=0 retry_at=0 failing=0
odd=0                   # the overlay printed something unexpected (reported once)
last_pass=$EPOCHREALTIME heard=$EPOCHREALTIME
while true; do
  # This loop was not running for a while (stopped, the Mac asleep): it cannot know whether the overlay spoke
  # meanwhile, so it listens again from now instead of calling it stuck.
  (( EPOCHREALTIME - last_pass > 2 )) && heard=$EPOCHREALTIME
  last_pass=$EPOCHREALTIME

  presses=( $nexts/*(N) )               # long presses: on to the next emoji, once per press
  if (( $#presses )); then
    zf_rm -f -- $presses
    from=$idx
    idx=$(( (idx - 1 + $#presses) % $#list + 1 ))
    keep_word
    pending=pop
  fi

  if [[ -z $opid ]]; then
    waiting=( $taps/*(N) )
    if (( $#waiting )); then
      if (( dry == 1 )); then
        zf_rm -f -- $waiting
        print -r -- "burst: $list[idx] x$#waiting"
        pending=burst
      elif (( EPOCHSECONDS >= start_at )); then
        start_overlay
      else
        zf_rm -f -- $waiting              # the overlay keeps failing: they would show far too late
      fi
    fi
  fi

  if [[ -n $opid ]]; then
    waited=$EPOCHREALTIME
    if { IFS= read -r -t 0.25 -p line } 2>/dev/null; then
      heard=$EPOCHREALTIME
      case $line in
        (up|.) ;;
        (burst) pending=burst; (( dry )) && print -r -- "burst: $list[idx]" ;;
        (bye) said_bye=1 ;;
        (*) (( odd )) || print -u2 -- "reactions: the overlay printed something unexpected"; odd=1 ;;
      esac
    elif (( EPOCHREALTIME - waited < 0.2 )); then     # no wait, no line: the overlay is gone
      opid=""
      if (( said_bye )); then
        fails=0                         # it quit by itself after keep_alive seconds without a tap
      else
        now=$EPOCHSECONDS
        (( now - began >= 60 )) && fails=0
        start_at=$(( now + waits[fails < 5 ? fails + 1 : 5] ))
        print -u2 -- "reactions: the overlay stopped; it can start again in $(( start_at - now )) s"
        (( fails++ ))
      fi
    elif (( EPOCHREALTIME - waited > 2 )); then       # this wait took far longer than asked: not running either
      heard=$EPOCHREALTIME
    elif (( EPOCHREALTIME - heard > 5 )); then        # it says something every second: silent longer, it is stuck
      print -u2 -- "reactions: the overlay went quiet; ending it"
      stop_overlay KILL
      start_at=$(( EPOCHSECONDS + 5 ))
    fi
  elif (( post_fd )); then
    zselect -t 25 -r $post_fd                         # a quarter of a second, or until the answer comes
  else
    zselect -t 25
  fi

  (( post_fd )) && post_check
  [[ -z $pending ]] && (( EPOCHSECONDS - posted_at >= keyframe )) && pending=rest
  if (( ! post_fd )) && [[ -n $pending ]] && (( EPOCHSECONDS >= retry_at )); then show $pending; pending=""; fi
done
