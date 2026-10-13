# Snow, the live loop (the button's startup script): lets it snow on the Mac's screen while the snow is on.
#
# The tap (the button's command) writes the second the snow ends to $dir/until, or removes the file to stop it.
# At rest this loop only looks at that file four times a second (a builtin read, no process started). While the
# file says snow, it keeps the overlay running: one osascript (JXA) process that draws falling snow over every
# display — see its own notes below. The loop keeps $dir/falling while it wants snow; once the file is gone
# the overlay lets no new flakes fall, fades the ones in the air as they fall and quits. The overlay also quits
# when this loop is gone, even killed (its parent changes), and this loop ends it at once on TERM, INT and HUP:
# the agent stops startup scripts when the phone disconnects and when it quits.
#
# The button keeps its own face (a snowflake, "Snow") at rest; while it snows, the same snowflake in icy blue.
# That is two posts a snowfall, each one curl call that runs beside this loop (a slow agent never holds it up);
# nothing is posted while nothing changes.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/system || { print -u2 -- "snow: zsh modules datetime/zselect/system are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm || { print -u2 -- "snow: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
until_file="$dir/until"         # the tap: the epoch second the snow ends. Gone: no snow
go_file="$dir/falling"          # this loop: here while it wants snow. The overlay watches it
icy="#64D2FF"                   # the colour of the button while it snows

snow_js='ObjC.import("AppKit");
ObjC.import("QuartzCore");
ObjC.import("CoreGraphics");
ObjC.bindFunction("getppid", ["int", []]);

// The snow over every display: one see-through window per display above everything (full screen apps too, every
// Space), clicks pass through, never focused, no Dock icon. The flakes are Core Animation particles
// (CAEmitterLayer), simulated and drawn by the window server at the refresh rate of the display; this process only looks
// around twice a second (and pauses the flakes while nobody can see them). Plain images drawn once into bitmaps: CGGradient and CGPath objects come
// through JXA as opaque refs that draw nothing, a CGImage handed to an id argument must go through
// ObjC.castRefToObject (a bare ref arrives as a dictionary and draws nothing), CFRelease from JXA crashes, and
// every colour is a CoreGraphics one kept for the whole process (the CGColor of a temporary NSColor is freed with it).
//
// argv[0]: a file the loop keeps while it wants snow. Gone: no new flakes, the ones in the air fade as they
// fall, and the process quits ("bye"). Back while they fade: it snows on. Prints "up" once the windows are up and
// "." every second; quits at once when the loop that started it is gone (its parent changes).

const SEED_TIME = 0.4;    // s: at the start a screenful of flakes is born all over the screen...
const SEED_FADE = 2.2;    // s: ...and comes up out of nothing over this long: the snow thickens
const FADE_OUT = 3;       // s: after a stop the flakes in the air fade while they fall
const MARGIN = 40;        // pt: flakes are born above the screen and live until below it
const LEAN = 0.06;        // rad: the snow drifts a little sideways...
const SPREAD = 0.12;      // rad: ...each flake up to this far either side of that (emissionRange is a half-angle)
const TILT = Math.abs(LEAN) + SPREAD;   // the most slanted fall
const HALO = 0.4;         // the faint dark shadow around every flake, so the snow shows on white too
// Three depths of soft round flakes and a few crystals. rho: flakes per 100×100 pt; v, vr: speed and its range
// (pt/s, v ± vr/2); s, sr: size and its range; spin: the range of turning speeds (rad/s) — a round flake sits
// off the centre of its image, so turning makes it circle: the sway. Smaller is slower and dimmer.
const DEPTHS = [
  { rho: 0.70, v: 22, vr: 8,  s: 0.36, sr: 0.10, a: 0.60, spin: 2.2 },
  { rho: 0.40, v: 36, vr: 10, s: 0.62, sr: 0.14, a: 0.82, spin: 2.0 },
  { rho: 0.15, v: 54, vr: 14, s: 0.95, sr: 0.24, a: 0.92, spin: 1.6 },
];
const CRYSTAL = { rho: 0.04, v: 40, vr: 10, s: 0.78, sr: 0.30, a: 0.95, spin: 1.0 };

const space = $.CGColorSpaceCreateWithName($.kCGColorSpaceSRGB);
const white = $.CGColorCreateSRGB(1, 1, 1, 1);
const shade = $.CGColorCreateSRGB(0, 0, 0, HALO);
const out = $.NSFileHandle.fileHandleWithStandardOutput;
const err = $.NSFileHandle.fileHandleWithStandardError;

function say(text) { out.writeData($(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function complain(text) { err.writeData($("snow: " + text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }

function bitmap(side, draw) {
  const ctx = $.CGBitmapContextCreate(null, side, side, 8, 0, space, 1);      // RGBA, premultiplied
  draw(ctx);
  return $.CGBitmapContextCreateImage(ctx);
}

// A soft round flake: only the blurred shadow of a disc drawn outside the image lands — a glow with no hard edge —
// over a wider, faint dark one that shows it on white. It sits d to the right of the centre of the image, which
// the particle turns about.
function dotImage(S, alpha) {
  const core = 4 * S, glow = 4.4 * S, dusk = 5.5 * S, d = 14 * S;
  const side = Math.ceil(2 * (d + core + 2 * dusk));               // the dark shadow fades out inside the image
  return bitmap(side, ctx => {
    const x = side / 2 + d, y = side / 2, away = 4 * side;
    const disc = $.CGRectMake(x - away - core, y - core, 2 * core, 2 * core);
    $.CGContextSetFillColorWithColor(ctx, white);
    $.CGContextSetShadowWithColor(ctx, $.CGSizeMake(away, 0), dusk, shade);
    $.CGContextFillEllipseInRect(ctx, disc);
    $.CGContextSetShadowWithColor(ctx, $.CGSizeMake(away, 0), glow, $.CGColorCreateSRGB(1, 1, 1, alpha));
    for (let i = 0; i < 2; i++) $.CGContextFillEllipseInRect(ctx, disc);          // twice: a denser glow
  });
}

// A six-armed crystal: arms with two pairs of branches, thin lines over a faint wider glow and a dark edge.
function crystalImage(S, alpha) {
  const L = 13.2 * S, side = Math.ceil(2 * L + 6 * S), c = side / 2;
  return bitmap(side, ctx => {
    $.CGContextSetLineCap(ctx, 1);
    $.CGContextSetLineJoin(ctx, 1);
    function arms(width, colour) {
      $.CGContextSetStrokeColorWithColor(ctx, colour);
      $.CGContextSetLineWidth(ctx, width);
      for (let k = 0; k < 6; k++) {
        const t = Math.PI / 2 + k * Math.PI / 3, dx = Math.cos(t), dy = Math.sin(t);
        $.CGContextMoveToPoint(ctx, c, c);
        $.CGContextAddLineToPoint(ctx, c + L * dx, c + L * dy);
        for (const [at, len] of [[0.45, 0.30], [0.72, 0.20]]) {
          const px = c + L * at * dx, py = c + L * at * dy;
          for (const turn of [-1, 1]) {
            const u = t + turn * Math.PI / 3;
            $.CGContextMoveToPoint(ctx, px, py);
            $.CGContextAddLineToPoint(ctx, px + L * len * Math.cos(u), py + L * len * Math.sin(u));
          }
        }
      }
      $.CGContextStrokePath(ctx);
    }
    arms(3.8 * S, shade);
    arms(3.4 * S, $.CGColorCreateSRGB(1, 1, 1, 0.16 * alpha));
    arms(1.3 * S, $.CGColorCreateSRGB(1, 1, 1, alpha));
  });
}

// The images, drawn once for the sharpest display (at least 2x: a 1x display gets them scaled down).
function images(S) {
  return { dots: DEPTHS.map(d => dotImage(S, d.a)), crystal: crystalImage(S, CRYSTAL.a), S: S };
}

// seeded: a cell of the emitter that fills the whole screen at the start; otherwise one of
// the steady emitter along the top. line: the width flakes are born along; height: that of the screen.
function cell(img, S, o, line, height, seeded) {
  const c = $.CAEmitterCell.emitterCell;
  const slow = o.v - o.vr / 2, per = o.rho / 1e4;
  c.setContents(ObjC.castRefToObject(img));          // a CGImage: a bare ref would reach CA as a dictionary
  c.setContentsScale(S);
  c.setMinificationFilter($.kCAFilterTrilinear);
  // Steady: as many a second as keep the density; seeded: a whole screen of them over SEED_TIME.
  c.setBirthRate(seeded ? per * line * height / SEED_TIME : per * line * o.v);
  // Long enough for the slowest, most slanted flake from the top of the band to fall out below the screen.
  c.setLifetime((height + 2.25 * MARGIN) / (slow * Math.cos(TILT)) + 1);
  c.setVelocity(o.v);
  c.setVelocityRange(o.vr);
  c.setEmissionLongitude(-Math.PI / 2 + LEAN);          // down: y grows upward in these layers
  c.setEmissionRange(SPREAD);
  c.setScale(o.s);
  c.setScaleRange(o.sr);
  c.setSpinRange(o.spin);
  c.setColor(white);
  return c;
}

function cells(im, line, height, seeded) {
  const list = DEPTHS.map((d, i) => cell(im.dots[i], im.S, d, line, height, seeded));
  list.push(cell(im.crystal, im.S, CRYSTAL, line, height, seeded));
  return $(list);
}

function number(x) { return $.NSNumber.numberWithDouble(x); }

// The layers of one display of W×H pt at the given backing scale: a root on its own clock, standing at time t,
// the steady band above the display and the start-up emitter over it.
function makeLayers(W, H, scale, im, t) {
  const root = $.CALayer.layer, top = $.CAEmitterLayer.layer, seed = $.CAEmitterLayer.layer;
  root.setFrame($.CGRectMake(0, 0, W, H));
  // The clock of the root is the time of the snow (paused here; run() starts it with clockTo). Everything below runs on it.
  root.setSpeed(0);
  root.setTimeOffset(t);
  // Flakes drift sideways as they fall: the band they are born in reaches out past both edges by as much.
  const side = H * Math.tan(TILT);
  const line = W + 2 * side + 2 * MARGIN;
  for (const e of [top, seed]) {
    e.setFrame($.CGRectMake(0, 0, W, H));
    e.setSeed(Math.floor(Math.random() * 4e9));
    e.setContentsScale(scale);
    root.addSublayer(e);
  }
  // A thin band just above the display, the same shape and mode as the seed emitter below: emission angles are
  // relative to the shape.
  top.setEmitterShape($.kCAEmitterLayerRectangle);
  top.setEmitterMode($.kCAEmitterLayerSurface);
  top.setEmitterPosition($.CGPointMake(W / 2, H + MARGIN));
  top.setEmitterSize($.CGSizeMake(line, MARGIN / 2));
  top.setEmitterCells(cells(im, line, H, false));
  seed.setEmitterShape($.kCAEmitterLayerRectangle);
  seed.setEmitterMode($.kCAEmitterLayerSurface);
  seed.setEmitterPosition($.CGPointMake(W / 2, H / 2));
  seed.setEmitterSize($.CGSizeMake(W, H));
  seed.setEmitterCells(cells(im, W, H, true));
  // The start: a screenful of flakes is born everywhere in the first moments, while this layer comes up from
  // nothing over SEED_FADE — the snow thickens. (Each flake fading in by itself would need alpha to stop at 1.)
  seed.setBirthRate(0);
  const burst = $.CABasicAnimation.animationWithKeyPath("birthRate");
  burst.setFromValue(number(1));
  burst.setToValue(number(1));
  burst.setBeginTime(t);
  burst.setDuration(SEED_TIME);
  seed.addAnimationForKey(burst, "seed");
  const rise = $.CABasicAnimation.animationWithKeyPath("opacity");
  rise.setFromValue(number(0));
  rise.setToValue(number(1));
  rise.setBeginTime(t);
  rise.setDuration(SEED_FADE);
  rise.setTimingFunction($.CAMediaTimingFunction.functionWithName($.kCAMediaTimingFunctionEaseInEaseOut));
  seed.addAnimationForKey(rise, "rise");
  return { root: root, top: top, seed: seed };
}

function makeScreen(screen, index, im, t) {
  const box = screen.frame;                                   // the window covers the display
  const w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(box, 0, 2, false);   // borderless, buffered
  w.setOpaque(false);
  w.setBackgroundColor($.NSColor.clearColor);
  w.setHasShadow(false);
  w.setIgnoresMouseEvents(true);
  w.setReleasedWhenClosed(false);
  w.setLevel(1000);                                           // the screen saver level
  w.setCollectionBehavior(1 | 16 | 64 | 256);   // all Spaces, stationary, out of the window cycle, full screen
  const view = w.contentView;
  view.setWantsLayer(true);
  const part = makeLayers(box.size.width, box.size.height, screen.backingScaleFactor, im, t);
  view.layer.addSublayer(part.root);
  w.orderFrontRegardless;
  part.window = w;
  return part;
}

// "<x> <y> <w> <h> <scale>" for every display: when it changes, the windows are made again.
function displays() {
  const screens = $.NSScreen.screens, list = [];
  for (let i = 0; i < Number(screens.count); i++) {
    const s = screens.objectAtIndex(i), f = s.frame;
    list.push([f.origin.x, f.origin.y, f.size.width, f.size.height, s.backingScaleFactor].join(" "));
  }
  return list.join(",");
}

function build(t) {
  const screens = $.NSScreen.screens, count = Number(screens.count);
  let S = 2;
  for (let i = 0; i < count; i++) S = Math.max(S, Number(screens.objectAtIndex(i).backingScaleFactor));
  const im = images(S), parts = [];
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  for (let i = 0; i < count; i++) {
    try { parts.push(makeScreen(screens.objectAtIndex(i), i, im, t)); }
    catch (e) { complain("no snow on display " + (i + 1) + ": " + e); }
  }
  $.CATransaction.commit;
  $.CATransaction.flush;
  return parts;
}

// Runs the clock of the flakes from snow time t with the display (the window server animates them at its own rate,
// smoothly), or stops it at t while nobody can see the snow.
function clockTo(parts, t, running) {
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  for (const p of parts) {
    if (running) { p.root.setSpeed(1); p.root.setTimeOffset(t - $.CACurrentMediaTime()); }
    else { p.root.setSpeed(0); p.root.setTimeOffset(t); }
  }
  $.CATransaction.commit;
  $.CATransaction.flush;
}

function takeDown(parts) {
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  for (const p of parts) p.window.orderOut(null);
  $.CATransaction.commit;
  $.CATransaction.flush;
}

function opacityNow(layer) {
  const shown = layer.presentationLayer;
  return shown.isNil() ? Number(layer.opacity) : Number(shown.opacity);
}

// Stop: no new flakes; the ones in the air fade out as they fall. Back: they come again. t: the time of the snow.
function setFalling(parts, falling, t) {
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  for (const p of parts) {
    const from = opacityNow(p.root), fade = $.CABasicAnimation.animationWithKeyPath("opacity");
    p.top.setBirthRate(falling ? 1 : 0);
    if (!falling) p.seed.removeAnimationForKey("seed");        // no more births; its fade-in (if any) goes on
    fade.setFromValue(number(from));
    fade.setToValue(number(falling ? 1 : 0));
    fade.setBeginTime(t);
    fade.setDuration(falling ? 1 : FADE_OUT);
    const curve = falling ? $.kCAMediaTimingFunctionEaseOut : $.kCAMediaTimingFunctionEaseIn;
    fade.setTimingFunction($.CAMediaTimingFunction.functionWithName(curve));
    p.root.setOpacity(falling ? 1 : 0);
    p.root.addAnimationForKey(fade, "fade");
  }
  $.CATransaction.commit;
  $.CATransaction.flush;
}

// AppKit learns about added and removed displays from events: take the waiting ones without blocking.
function takeEvents() {
  const app = $.NSApplication.sharedApplication;
  for (let i = 0; i < 64; i++) {
    const e = app.nextEventMatchingMaskUntilDateInModeDequeue($.NSEventMaskAny, $.NSDate.distantPast,
      $.NSDefaultRunLoopMode, true);
    if (e.isNil()) break;
  }
}

// Nobody can see the snow: the screen is locked (the lock screen covers it) or every display sleeps. Whatever
// cannot be read counts as seen: a wrong "hidden" would stop the snow in front of someone.
function hidden() {
  try {
    const session = ObjC.castRefToObject($.CGSessionCopyCurrentDictionary());    // a small copy, never released
    const locked = session.objectForKey($("CGSSessionScreenIsLocked"));
    if (!locked.isNil() && locked.boolValue) return true;
    const screens = $.NSScreen.screens, n = Number(screens.count);
    for (let i = 0; i < n; i++) {
      const id = screens.objectAtIndex(i).deviceDescription.objectForKey($("NSScreenNumber"));
      if (id.isNil() || !$.CGDisplayIsAsleep(id.unsignedIntValue)) return false;
    }
    return n > 0;
  } catch (e) { return false; }
}

function run(argv) {
  const go = argv[0] || "", files = $.NSFileManager.defaultManager, parent = $.getppid();
  const wanted = () => files.fileExistsAtPath($(go));
  if (!go || !wanted()) return;
  $.NSApplication.sharedApplication.setActivationPolicy(1);  // accessory: no Dock icon, never active
  // Two clocks. t, seconds since the start by the uptime of the system: it never jumps when the clock is set, nor over
  // a sleep. snow, the time of the flakes: it stands still while nobody can see them, and they fall on from there.
  const info = $.NSProcessInfo.processInfo, up0 = info.systemUptime, clock = () => info.systemUptime - up0;
  let parts = build(0), layout = displays(), falling = true, fadeEnds = 0;
  let snow = 0, last = 0, seen = true;
  let look = 0.5, beat = 1, survey = 2;
  if (!parts.length) { complain("no display to snow on"); return; }
  clockTo(parts, snow, true);
  try { say("up"); } catch (e) { takeDown(parts); return; }
  for (;;) {
    const t = clock();
    if (seen) snow += t - last;
    last = t;
    if (t >= look) {                                                  // twice a second: look around
      look = t + 0.5;
      if ($.getppid() !== parent) { takeDown(parts); return; }        // the loop is gone: so is the snow
      const was = seen;
      seen = !hidden();
      if (seen !== was) clockTo(parts, snow, seen);
      const want = wanted();
      if (falling && !want) { setFalling(parts, false, snow); falling = false; fadeEnds = t + FADE_OUT; }
      else if (!falling && want) {                                  // tapped again while fading: snow on
        setFalling(parts, true, snow);
        falling = true;
        try { say("up"); } catch (e) { takeDown(parts); return; }
      }
      else if (!falling && t >= fadeEnds) { takeDown(parts); try { say("bye"); } catch (e) {} return; }
      if (t >= beat) {
        beat = t + 1;
        try { say("."); } catch (e) { takeDown(parts); return; }
      }
      if (falling && t >= survey) {                                   // a display came or went: snow on the new set
        survey = t + 2;
        takeEvents();
        const now = displays();
        if (now !== layout) {
          takeDown(parts);
          parts = build(snow);
          clockTo(parts, snow, seen);
          layout = now;
        }
      }
    }
    // Nothing to do until the next look: the window server moves the flakes.
    delay(Math.max(0.005, look - clock()));
  }
}
'

opid=""                 # the overlay
post_fd=0 post_pid=0    # a post on its way: the pipe its answer comes back on, and its curl
# stop_overlay [signal]: ends the overlay (TERM; KILL for one that does not answer). Its windows go with it.
stop_overlay() { [[ -n $opid ]] && kill -${1:-TERM} $opid 2>/dev/null; opid="" }
# drop_post: forgets a post on its way and ends its curl.
drop_post() { (( post_pid )) && kill $post_pid 2>/dev/null; (( post_fd )) && exec {post_fd}<&-; post_fd=0 post_pid=0 }
trap 'stop_overlay; drop_post; zf_rm -f -- $go_file; exit 0' TERM INT HUP
trap 'stop_overlay; drop_post' EXIT

# REPLY = the second the snow ends, when the tap left one that is still ahead. Returns 1 without: no snow.
snow_until() {
  local line=""
  REPLY=""
  { IFS= read -r line < $until_file } 2>/dev/null
  [[ $line == <-> ]] && (( ${#line} <= 12 && line > EPOCHSECONDS && line <= EPOCHSECONDS + 86400 )) || return 1
  REPLY=$line
}

# The overlay, as a coprocess: its lines ("up", a "." every second, "bye") come back to this loop.
start_overlay() {
  zf_mkdir -p -- $dir 2>/dev/null
  { : >> $go_file } 2>/dev/null || { print -u2 -- "snow: cannot write in $dir"; return 1 }
  coproc osascript -l JavaScript -e "$snow_js" -- $go_file
  opid=$! began=$EPOCHSECONDS heard=$EPOCHREALTIME said_bye=0
}

# post_start <snow | rest>: sends it to the button without waiting for the answer. curl runs beside this loop
# (first its pid, then the body and the status on the last line come back on post_fd); post_check reads it. The
# token goes from the environment into the request by curl itself, never on a command line.
post_start() {
  local json
  if [[ $1 == snow ]]; then json="{\"cellId\":\"$cell\",\"icon\":\"snowflake\",\"color\":\"$icy\"}"
  else json="{\"cellId\":\"$cell\",\"reset\":true}"; fi
  exec {post_fd}< <(print -r -- $sysparams[pid]; exec curl -q -sS --max-time 3 -w '\n%{http_code}\n' \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H 'Content-Type: application/json' --data-binary "$json" http://127.0.0.1:9848/api/update-button 2>&1) ||
    { post_fd=0; return 1 }
  post_pid=0 posting=$1 answer=""
  { IFS= read -r -t 1 -u $post_fd post_pid } 2>/dev/null
  [[ $post_pid == <-> ]] || post_pid=0
}

# post_check: never waits — it takes only the bytes already there (sysread, not a line read that would wait for
# the rest of a line). Once the whole answer is in: shown = what was posted when the agent took it; otherwise
# the failure is reported once and the next try waits 2 s.
post_check() {
  local chunk
  while zselect -t 0 -r $post_fd; do
    if sysread -i $post_fd chunk 2>/dev/null; then answer+=$chunk; continue; fi
    exec {post_fd}<&-                               # the end (or a broken pipe): the post is over
    post_fd=0 post_pid=0
    answer=${answer%$'\n'}
    if [[ ${answer##*$'\n'} == 200 ]]; then shown=$posting failing=0
    else
      (( failing )) || print -u2 -- "snow: update-button did not take it: ${${answer//$'\n'/ }[1,200]}"
      failing=1 retry_at=$(( EPOCHSECONDS + 2 ))
    fi
    return
  done
}

zf_rm -f -- $go_file 2>/dev/null        # left behind by a loop that was killed
waits=(5 10 20 40 60)                   # after the overlay failed: seconds before the next try
shown=""                # what the button shows: snow, rest; "" not known yet (so the first pass posts rest)
up=0                    # the overlay said it is up: the button shows snow
fails=0 start_at=0      # the overlay failed so many times in a row; when to try again
stop_by=0               # after a stop: when an overlay still running is ended
retry_at=0 failing=0    # after a failed post: when to post again; a failure was reported
odd=0                   # the overlay printed something unexpected (reported once)
last_pass=$EPOCHREALTIME
while true; do
  now=$EPOCHSECONDS
  # This loop was not running for a while (stopped, the Mac asleep): it cannot know whether the overlay spoke
  # meanwhile, so it listens again from now instead of calling it stuck.
  (( EPOCHREALTIME - last_pass > 2 )) && heard=$EPOCHREALTIME
  last_pass=$EPOCHREALTIME
  if snow_until; then want=1; else want=0; fi
  if (( want )); then
    stop_by=0
    [[ -e $go_file ]] || { : >> $go_file } 2>/dev/null
    [[ -z $opid ]] && (( now >= start_at )) && { start_overlay || start_at=$(( now + 30 )) }
  else
    up=0 fails=0 start_at=0
    [[ -e $go_file ]] && zf_rm -f -- $go_file
    if [[ -n $opid ]]; then             # it fades out and quits by itself in a few seconds
      (( stop_by )) || stop_by=$(( now + 10 ))
      (( now >= stop_by )) && { print -u2 -- "snow: the overlay did not stop by itself; ended"; stop_overlay KILL }
    fi
  fi

  if [[ -n $opid ]]; then
    waited=$EPOCHREALTIME
    if { IFS= read -r -t 0.25 -p line } 2>/dev/null; then
      heard=$EPOCHREALTIME
      case $line in
        (up) up=1 ;;
        (.) ;;
        (bye) said_bye=1 ;;
        (*) (( odd )) || print -u2 -- "snow: the overlay printed something unexpected"; odd=1 ;;
      esac
    elif (( EPOCHREALTIME - waited < 0.2 )); then     # no wait, no line: the overlay is gone
      opid="" stop_by=0
      if (( want )); then
        up=0
        if (( said_bye )); then
          start_at=0                    # it had faded out; tapped on again since: a fresh snowfall
        else
          now=$EPOCHSECONDS
          (( now - began >= 60 )) && fails=0
          start_at=$(( now + waits[fails < 5 ? fails + 1 : 5] ))
          print -u2 -- "snow: the overlay stopped; starting it again in $(( start_at - now )) s"
          (( fails++ ))
        fi
      fi
    elif (( EPOCHREALTIME - waited > 2 )); then       # this wait took far longer than asked: not running either
      heard=$EPOCHREALTIME
    elif (( EPOCHREALTIME - heard > 5 )); then        # it says something every second: silent longer, it is stuck
      print -u2 -- "snow: the overlay went quiet; ending it"
      stop_overlay KILL
      up=0 start_at=$(( EPOCHSECONDS + 5 ))
    fi
  elif (( post_fd )); then
    zselect -t 25 -r $post_fd                         # a quarter of a second, or until the answer comes
  else
    zselect -t 25
  fi

  if (( want && up )); then face=snow; else face=rest; fi
  (( post_fd )) && post_check
  if (( ! post_fd )) && [[ $face != "$shown" ]] && (( EPOCHSECONDS >= retry_at )); then post_start $face; fi
done
