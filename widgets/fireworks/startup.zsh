# Fireworks, the live loop (the button's startup script). A tap sends a salvo of rockets up the Mac's screen, a long
# press the grand finale: they burst into coloured sparks over the display the pointer is on, above every window, and
# clicks go through them.
#
# How it works. The tap and the long press only leave notes: an empty file each in $dir/shows, named by its time and
# kind. A note starts the overlay: one osascript (JXA) process that draws the shows (see its own notes below). The
# overlay reads the notes itself, a dozen times a second, so while it runs a tap shows at once; it stays up keep_alive
# seconds after the last show has burnt out and then quits, and the next tap starts it again (about half a second).
# It also quits when this loop is gone, even killed, and this loop ends it on TERM, INT and HUP: the agent stops
# startup scripts when the phone disconnects and when it quits. While the overlay is down this loop looks at the
# folder four times a second (a builtin glob, no process).
#
# The button keeps its own look at rest and turns gold while a show plays: two posts a show, each one curl call that
# runs beside this loop (a slow agent never holds it up); nothing is posted while nothing changes.
#
# Tool modes, no network and no window: --check prints what a salvo and a finale set up, read back from the emitters,
# and how many particles are alive at the busiest moment; --preview <out.png> draws the particle images and frames of
# a salvo and of a finale as Core Animation renders them offscreen. Any other argument prints the usage.
# FIREWORKS_DRY=1 runs the loop but prints the posts instead of sending them and the shows instead of drawing them;
# FIREWORKS_DRY=2 prints the posts and draws the shows for real (on screen: for a check with someone watching).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/system || { print -u2 -- "fireworks: zsh modules datetime/zselect/system are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm || { print -u2 -- "fireworks: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
shows="$dir/shows"              # the tap and the long press: an empty file each, named by its time and kind
pid_file="$dir/loop"            # this loop: its pid, so a tap knows something will draw it
keep_alive=150                  # s the overlay stays up after the last show, so the next tap shows at once
lit="#FFB340"                   # the colour of the button while a show plays
dry=${FIREWORKS_DRY:-0}
[[ $dry == [012] ]] || dry=0

overlay_js='ObjC.import("AppKit");
ObjC.import("QuartzCore");
ObjC.bindFunction("getppid", ["int", []]);

// Fireworks over the screen of the Mac. One see-through window per display, above everything (full screen apps too,
// every Space): clicks pass through, never focused, no Dock icon, and on screen only while a show plays. Every rocket
// is two Core Animation emitters (CAEmitterLayer) set up once, when its show starts, with all their timing ahead on
// the clock of the layers: the window server plays the whole show at the refresh rate of the display, and this
// process only reads the folder of notes a dozen times a second and takes away what has burnt out.
//
// The rocket: one particle that rises under gravity, sheds a trail of embers (a sub-cell of it) and dies at the top
// of its flight. The burst: a second emitter at that very place and moment, a flash and the sparks, which the air slows
// down (the "drag" behaviour of the layer), sink a little and fade, each drawing a short tail of embers. Two layers,
// because drag slows every particle of its layer: the rocket flies free, so its path is p + vt + at^2/2 exactly and
// the burst knows where it will be.
//
// Core Animation facts this relies on, checked offscreen (CARenderer) on macOS 26. A cell emits its first particle
// the moment its window (beginTime, duration) opens and then birthRate a second: birthRate x duration = n - 0.5 gives
// n particles and anything below 1 exactly one, at any refresh rate, but only when the emitter was already running as
// the window opened (hence LEAD). Sub-cells count time from the birth of their parent, aim relative to its heading
// (pi: backwards), do not take its speed and multiply its colour; a parent that stands still has no heading and its
// sub-cells show nothing (so a rocket bursts while it still rises: SLOW). emissionRange pi scatters over a sphere
// (seen from the side, a disc denser at the rim); a circle outline emitter with no range makes a flat ring. Drag
// ("CAEmitterBehavior", not in the public headers) is used only when this macOS has it; without it the sparks fly
// at a steady speed. The images are plain bitmaps drawn once (a soft dot is the blurred shadow of a disc drawn
// outside the image); a CGImage handed to an id argument goes through ObjC.castRefToObject (a bare ref draws
// nothing); colours are CoreGraphics ones kept for the whole process; CFRelease from JXA crashes.
//
// argv: <dir> <seconds>. <dir>/shows holds one empty file per tap or long press, named by its time and kind
// ("1727780000.123456.512.salvo" or ".finale"): each becomes a show over the display under the pointer and is
// removed. Prints "up" once, "show <kind> <rockets> <seconds>" for every show, "quiet" when the last one has burnt
// out, "." every second and "bye" when it quits by itself, <seconds> after the last show. Quits at once when the
// loop that started it is gone (its parent changes).
// Tool modes, no window: --check, --preview <out.png> (see the end of this script).

const FRESH = 6;          // s: an older note is dropped (the loop was busy starting this process, the Mac slept)
const POLL = 1 / 12;      // s: how often the folder of notes is read
const LEAD = 0.2;         // s: from setting a show up to its first rocket (the emitters run before a window opens)
const STAGGER = 0.35;     // s: shows asked for in one read start this far apart
const MOST = 40;          // rockets in the air at most; a show that would take more is dropped
const ONE = 0.1;          // s: the window of a cell that emits exactly one particle (at 7 a second: 0.7 of one)
const BURST = 0.04;       // s: the window the sparks of a burst are born in
const Y0 = -4;            // pt: rockets leave from just below the bottom edge
const SLOW = 0.12;        // share of its launch speed a rocket still has as it bursts
const SIZE = 900;         // pt: the display height the sizes below are for; others scale with their height

// The festive colours (sRGB) and the second colours that go with each.
const PALETTE = {
  red: [1, 0.24, 0.3], orange: [1, 0.55, 0.16], gold: [1, 0.8, 0.32], lime: [0.62, 1, 0.3],
  green: [0.24, 1, 0.56], cyan: [0.3, 0.9, 1], blue: [0.42, 0.58, 1], violet: [0.72, 0.45, 1],
  pink: [1, 0.42, 0.78], silver: [0.93, 0.95, 1],
};
const PARTNERS = {
  red: ["gold", "silver", "cyan"], orange: ["blue", "silver", "violet"], gold: ["red", "violet", "blue", "green"],
  lime: ["violet", "pink"], green: ["gold", "pink", "silver"], cyan: ["pink", "gold", "red"],
  blue: ["silver", "gold", "orange"], violet: ["gold", "cyan", "lime"], pink: ["silver", "cyan", "green"],
  silver: ["red", "blue", "violet"],
};
const NAMES = Object.keys(PALETTE);
// The kinds of burst. peony: one colour all round; mix: two colours mixed; pistil: one colour round a heart of the
// other; ring: a flat ring round a small heart; willow: gold sparks that hang and trail down long; glitter: a peony
// whose sparks twinkle as they die.
const KINDS = ["peony", "mix", "pistil", "ring", "willow", "glitter"];

const space = $.CGColorSpaceCreateWithName($.kCGColorSpaceSRGB);
function srgb(c, a) { return $.CGColorCreateSRGB(c[0], c[1], c[2], a); }
const COLOURS = {};
for (const name of NAMES) {
  const c = PALETTE[name];
  COLOURS[name] = { spark: srgb(c, 1), flash: srgb(c.map(x => x + (1 - x) * 0.7), 0.9) };
}
const WHITE = srgb([1, 1, 1], 1);
const HEAD = srgb([1, 0.9, 0.68], 0.9);       // the rocket
const TRAIL = srgb([1, 0.72, 0.4], 0.9);      // its embers
const WILLOW = srgb([1, 0.76, 0.36], 1);      // the gold of a willow
const DUST = srgb([1, 0.9, 0.72], 0.9);       // what a willow spark leaves behind (times its own gold)
const STREAK = srgb([1, 1, 1], 0.75);         // the tail of a spark (times its own colour)

const out = $.NSFileHandle.fileHandleWithStandardOutput;
const err = $.NSFileHandle.fileHandleWithStandardError;
function say(text) { out.writeData($(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function complain(text) { err.writeData($("fireworks: " + text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function number(x) { return $.NSNumber.numberWithDouble(x); }

// Drag, when this macOS has it.
const DRAG = (() => {
  try {
    if (typeof $.CAEmitterBehavior !== "function") return false;
    if (!$.CAEmitterLayer.layer.respondsToSelector("setEmitterBehaviors:")) return false;
    return !$.CAEmitterBehavior.behaviorWithType($("drag")).isNil();
  } catch (e) { return false; }
})();
function drag(k) {
  const b = $.CAEmitterBehavior.behaviorWithType($("drag"));
  b.setValueForKey(number(k), $("drag"));
  return b;
}

// Park-Miller: the tool modes show the same shows every time; live shows take Math.random.
function seeded(seed) {
  let s = seed % 2147483647;
  if (s <= 0) s += 2147483646;
  return () => (s = s * 16807 % 2147483647) / 2147483647;
}
function pick(rand, list) { return list[Math.floor(rand() * list.length)]; }
function shuffled(rand, list) {
  for (let i = list.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)), x = list[i]; list[i] = list[j]; list[j] = x; }
  return list;
}

// --- The plan of a show: numbers only ------------------------------------------------------------------------------

// One rocket: it leaves (x0, Y0) at `at` s into its show and bursts T s later at (xb, yb) into a burst of its kind
// that spreads to about R pt, in colours c1 and c2. big: the size of the burst against the usual one.
function rocket(rand, W, H, at, x0, xb, kind, big) {
  const R = H * (kind === "willow" ? 0.17 : 0.15) * big * (1 + 0.35 * rand());
  const c1 = kind === "willow" ? "gold" : pick(rand, NAMES);
  const yb = Math.max(H * 0.45, Math.min(H * 0.97 - R, H * (0.56 + 0.26 * rand())));
  const edge = Math.min(W * 0.45, R * 0.5 + W * 0.05);
  return { at: at, x0: x0, xb: Math.min(W - edge, Math.max(edge, xb)), yb: yb, T: 1.05 + 0.3 * rand(), kind: kind,
           R: R, c1: c1, c2: pick(rand, PARTNERS[c1]), seed: Math.floor(rand() * 4e9) };
}

// n kinds in a row, never the same twice running, at most `willows` willows.
function kinds(rand, n, willows) {
  const list = [];
  while (list.length < n) {
    const k = pick(rand, KINDS);
    if (k === list[list.length - 1] || (k === "willow" && list.filter(x => x === k).length >= willows)) continue;
    list.push(k);
  }
  return list;
}

// A tap: three to five rockets from across the bottom over about three seconds, now and then two nearly together.
function salvo(rand, W, H) {
  const n = 3 + Math.floor(rand() * 3), list = kinds(rand, n, 1), bands = shuffled(rand, [...Array(n).keys()]);
  const rockets = [];
  let t = 0;
  for (let i = 0; i < n; i++) {
    if (i) t += rand() < 0.25 ? 0.06 + 0.1 * rand() : 0.55 + 0.4 * rand();
    const x0 = W * (0.12 + 0.76 * (bands[i] + 0.15 + 0.7 * rand()) / n);
    rockets.push(rocket(rand, W, H, t, x0, x0 + (rand() - 0.5) * 0.1 * W, list[i], 1));
  }
  return rockets;
}

// A long press: the grand finale, launches for about five and a half seconds, most of them from the sides and aimed
// inwards. From the sides one by one, then from everywhere and faster, then pairs from both sides at once with
// willows hanging high in the middle, and a last volley of five together.
function finale(rand, W, H) {
  const rockets = [];
  const side = left => W * (left ? 0.04 + 0.14 * rand() : 0.82 + 0.14 * rand());
  const inward = x => x + (x < W / 2 ? 1 : -1) * W * (0.04 + 0.08 * rand());
  const any = () => pick(rand, ["peony", "mix", "pistil", "ring", "glitter"]);
  let t = 0;
  for (let i = 0; i < 6; i++, t += 0.26 + 0.1 * rand()) {
    const x0 = side(i % 2 === 0);
    rockets.push(rocket(rand, W, H, t, x0, inward(x0), any(), 0.85));
  }
  t += 0.1;
  for (let i = 0; i < 8; i++, t += 0.2 + 0.12 * rand()) {
    const x0 = i % 2 ? W * (0.3 + 0.4 * rand()) : side(rand() < 0.5);
    rockets.push(rocket(rand, W, H, t, x0, i % 2 ? x0 : inward(x0), i === 5 ? "willow" : any(), 0.85));
  }
  for (let i = 0; i < 3; i++, t += 0.38 + 0.08 * rand()) {
    for (const left of [true, false]) {
      const x0 = side(left);
      rockets.push(rocket(rand, W, H, t + 0.04 * rand(), x0, inward(x0), any(), 0.9));
    }
    if (i < 2) rockets.push(rocket(rand, W, H, t + 0.18, W * (0.38 + 0.24 * rand()), W * (0.38 + 0.24 * rand()), "willow", 1.1));
  }
  t += 0.15;
  ["glitter", "peony", "mix", "ring", "glitter"].forEach((kind, i) => {
    const x0 = W * (0.1 + 0.8 * (i + 0.5) / 5);
    rockets.push(rocket(rand, W, H, t + 0.06 * rand(), x0, x0, kind, 1.1));
  });
  return rockets;
}

// The launch of rocket r: speed (pt/s), heading (rad) and gravity (pt/s^2) that bring it from (x0, Y0) to (xb, yb) in
// T s, still rising at SLOW of its launch speed.
function flight(r) {
  const vy = 2 * (r.yb - Y0) / (r.T * (1 + SLOW)), vx = (r.xb - r.x0) / r.T;
  return { speed: Math.hypot(vx, vy), heading: Math.atan2(vy, vx), g: (1 - SLOW) * vy / r.T };
}

// --- Images and emitters -------------------------------------------------------------------------------------------

function bitmap(side, draw) {
  const ctx = $.CGBitmapContextCreate(null, side, side, 8, 0, space, 1);      // RGBA, premultiplied
  draw(ctx);
  return $.CGBitmapContextCreateImage(ctx);
}

// A soft white dot in the middle of a side x side px image: for each [radius, blur, alpha] only the blurred shadow of
// a disc drawn outside the image lands, a glow with no hard edge.
function softDot(side, layers) {
  return bitmap(side, ctx => {
    const c = side / 2, away = 4 * side;
    $.CGContextSetFillColorWithColor(ctx, WHITE);
    for (const [r, blur, a] of layers) {
      $.CGContextSetShadowWithColor(ctx, $.CGSizeMake(away, 0), blur, srgb([1, 1, 1], a));
      $.CGContextFillEllipseInRect(ctx, $.CGRectMake(c - away - r, c - r, 2 * r, 2 * r));
    }
  });
}

// The images, drawn once at S px a point (the sharpest display, at least 2x): a spark (a bright core in a soft glow,
// 14 pt), an ember (a small soft dot, 8 pt: trails, tails, dust, twinkles) and a glow (the flash, 72 pt). White: each
// cell tints them with its colour. (Cast: a CGImage for an id argument; CoreGraphics takes the same object as is.)
function images(S) {
  const make = (pt, layers) => ObjC.castRefToObject(softDot(Math.ceil(pt * S), layers.map(([r, b, a]) => [r * S, b * S, a])));
  return {
    spark: make(14, [[1.3, 4.5, 0.45], [1.4, 1.2, 1], [1, 0.6, 1]]),
    ember: make(8, [[0.8, 1.8, 0.5], [0.8, 0.6, 1]]),
    glow: make(72, [[9, 20, 0.8], [4, 7, 1]]),
    S: S,
  };
}

function emitterLayer(W, H, x, y, scale, seed) {
  const e = $.CAEmitterLayer.layer;
  e.setFrame($.CGRectMake(0, 0, W, H));
  e.setEmitterPosition($.CGPointMake(x, y));
  e.setRenderMode($.kCAEmitterLayerAdditive);           // sparks add up where they cross: they glow
  e.setSeed(seed % 4294967296);
  e.setContentsScale(scale);
  return e;
}

function cellOf(img, S) {
  const c = $.CAEmitterCell.emitterCell;
  c.setContents(img);
  c.setContentsScale(S);
  return c;
}
// Exactly one particle the moment `at` comes; n particles within BURST s from then.
function once(c, at) { c.setBeginTime(at); c.setDuration(ONE); c.setBirthRate(7); }
function many(c, at, n) { c.setBeginTime(at); c.setDuration(BURST); c.setBirthRate((n - 0.5) / BURST); }

// The tail every spark draws behind it: embers in its colour that shrink and fade within a third of a second. Dense
// while the spark is fast (one every few points: a streak), sparse once the air has slowed it down.
function streaks(im, q) {
  return [[0, 0.5, 40, 0.22], [0.5, 0, 10, 0.28]].map(([begin, dur, rate, life]) => {
    const c = cellOf(im.ember, im.S);
    c.setBeginTime(begin);
    if (dur) c.setDuration(dur);
    c.setBirthRate(rate);
    c.setLifetime(life); c.setLifetimeRange(0.1);
    c.setAlphaSpeed(-0.75 / life);
    c.setScale(1.1 * q); c.setScaleSpeed(-1.8 * q);
    c.setColor(STREAK);
    return c;
  });
}

// What a willow spark leaves as it falls: embers that hang in the air and sink slowly.
function dust(im, q, u) {
  const c = cellOf(im.ember, im.S);
  c.setBirthRate(26);
  c.setLifetime(1.2); c.setLifetimeRange(0.6);
  c.setYAcceleration(-25 * u);
  c.setAlphaSpeed(-0.6);
  c.setScale(1.1 * q); c.setScaleRange(0.3 * q); c.setScaleSpeed(-0.4 * q);
  c.setColor(DUST);
  return c;
}

// The twinkles of a glitter spark late in its life: brief bright flickers in its colour.
function twinkle(im, q) {
  const c = cellOf(im.ember, im.S);
  c.setBeginTime(0.9); c.setDuration(1.4);
  c.setBirthRate(4);
  c.setLifetime(0.08);
  c.setScale(1.7 * q);
  c.setColor(WHITE);
  return c;
}

// The burst of rocket r at `at` on the clock of its layers: a flash and the sparks of its kind. q: the size of
// particles, u: of distances (the display against SIZE). tail: s from `at` until its last particle is gone.
// Every colour of sparks has a layer of its own, the flash goes with the first: in one layer Core Animation loses the
// image of every top-level cell listed after one with sub-cells and draws it as a plain square (checked offscreen).
function burst(r, at, im, scale, W, H, q, u) {
  const k = r.kind === "willow" ? 2.1 : 1.6;
  const speed = R => DRAG ? R * k : R / 1.5;            // dragged, a spark stops at its speed / k
  const groups = [[]];
  let tail = 0.4, colours = 0;
  // n sparks of one colour at speed v. o: life, spread (of lives), ring (all at one speed, flat), fall (gravity
  // against SIZE), size, kids (sub-cells besides the tail), dust (a willow: no tail), after (how long kids outlive it).
  function sparks(n, colour, v, o) {
    const c = cellOf(im.spark, im.S), life = o.life || 2.1, spread = o.spread === undefined ? 0.8 : o.spread;
    many(c, at, n);
    c.setLifetime(life); c.setLifetimeRange(spread);
    c.setVelocity(v); c.setVelocityRange(o.ring ? 0 : v * 0.16);
    c.setEmissionRange(o.ring ? 0 : Math.PI);
    c.setYAcceleration(-(o.fall || 80) * u);
    c.setAlphaSpeed(-1 / (life + spread / 2));
    const s = (o.size || 0.9) * q;
    c.setScale(s); c.setScaleRange(s * 0.3); c.setScaleSpeed(-s * 0.12);
    c.setColor(colour);
    c.setEmitterCells($((o.kids || []).concat(o.dust ? [] : streaks(im, q))));
    if (colours++) groups.push([]);                       // a second colour: a layer of its own
    groups[groups.length - 1].push(c);
    tail = Math.max(tail, life + spread / 2 + (o.after || 0.4));
  }
  const flash = cellOf(im.glow, im.S);
  once(flash, at);
  flash.setLifetime(0.32);
  flash.setScale(0.9 * q * Math.sqrt(r.R / (0.17 * H))); flash.setScaleSpeed(1.6 * q);
  flash.setAlphaSpeed(-3);
  flash.setColor(COLOURS[r.c1].flash);
  groups[0].push(flash);
  const c1 = COLOURS[r.c1].spark, c2 = COLOURS[r.c2].spark;
  switch (r.kind) {
    case "peony": sparks(120, c1, speed(r.R), {}); break;
    case "mix": sparks(64, c1, speed(r.R), {}); sparks(64, c2, speed(r.R), {}); break;
    case "pistil": sparks(90, c1, speed(r.R), {}); sparks(40, c2, speed(r.R * 0.45), { size: 0.6, life: 1.6, spread: 0.6 }); break;
    case "ring":
      sparks(76, c1, speed(r.R), { ring: true });
      sparks(24, c2, speed(r.R * 0.32), { size: 0.6, life: 1.5, spread: 0.5 });
      break;
    case "willow": sparks(56, WILLOW, speed(r.R * 0.9), { life: 3.2, fall: 120, size: 0.7, kids: [dust(im, q, u)], dust: true, after: 1.6 }); break;
    default: sparks(100, c1, speed(r.R), { kids: [twinkle(im, q)] }); break;      // glitter
  }
  const layers = groups.map((cells, i) => {
    const e = emitterLayer(W, H, r.xb, r.yb, scale, r.seed + 1 + i);
    if (DRAG) e.setEmitterBehaviors($([drag(k)]));
    if (r.kind === "ring" && i === 0) {                   // the ring: born on a tiny circle, flying straight out
      e.setEmitterShape($.kCAEmitterLayerCircle);
      e.setEmitterMode($.kCAEmitterLayerOutline);
      e.setEmitterSize($.CGSizeMake(2, 2));
    }
    e.setEmitterCells($(cells));
    return e;
  });
  return { layers: layers, tail: tail };
}

// The emitters of rocket r (the rocket, then its burst), its launch `start` s into the clock of its layers. Returns
// them with the time, from the start of that clock, its last particle is gone.
function rocketLayers(r, start, im, scale, W, H) {
  const q = Math.min(1.4, Math.max(0.85, H / SIZE)), u = H / SIZE;
  const f = flight(r), at = start + r.at, top = at + r.T;
  const up = emitterLayer(W, H, r.x0, Y0, scale, r.seed);
  const head = cellOf(im.spark, im.S);
  once(head, at);
  head.setLifetime(r.T);                                    // it goes out as it bursts
  head.setVelocity(f.speed);
  head.setEmissionLongitude(f.heading);
  head.setYAcceleration(-f.g);
  head.setScale(0.65 * q);
  head.setColor(HEAD);
  const trail = cellOf(im.ember, im.S);
  trail.setBirthRate(140);
  trail.setLifetime(0.6); trail.setLifetimeRange(0.3);
  trail.setVelocity(35 * u); trail.setVelocityRange(50 * u);
  trail.setEmissionLongitude(Math.PI);                      // backwards
  trail.setEmissionRange(0.3);
  trail.setYAcceleration(-90 * u);
  trail.setAlphaSpeed(-0.85);
  trail.setScale(1.5 * q); trail.setScaleRange(0.5 * q); trail.setScaleSpeed(-1.3 * q);
  trail.setColor(TRAIL);
  head.setEmitterCells($([trail]));
  up.setEmitterCells($([head]));
  const b = burst(r, top, im, scale, W, H, q, u);
  return { layers: [up].concat(b.layers), ends: top + Math.max(0.8, b.tail) };
}

// Sets up the rockets of one show on root: their layers start on the clock now (begin, media time), the first rocket
// LEAD + delay s later. Returns the layers (all, and rocket by rocket) and the time from begin until all of it has
// burnt out.
function launch(root, rockets, begin, delay, im, scale, W, H) {
  const layers = [], each = [];
  let length = 0;
  for (const r of rockets) {
    const p = rocketLayers(r, LEAD + delay, im, scale, W, H);
    for (const l of p.layers) { l.setBeginTime(begin); root.addSublayer(l); layers.push(l); }
    each.push(p.layers);
    length = Math.max(length, p.ends);
  }
  return { layers: layers, each: each, length: length };
}

// --- Live ----------------------------------------------------------------------------------------------------------

// The display under the pointer and its key ("x y w h scale": a window per key).
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
  return { frame: f, scale: Number(pick.backingScaleFactor),
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
  return { window: w, root: root, shows: [], shown: false };
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
  if (argv[0] === "--check") return check();
  if (argv[0] === "--preview") return preview(argv.slice(1));
  const dir = argv[0] || "", rest = Number(argv[1]) || 150;
  if (!dir) { complain("usage: <dir> <seconds> | --check | --preview <out.png>"); return; }
  const files = $.NSFileManager.defaultManager, parent = $.getppid(), notes = $(dir + "/shows");
  const info = $.NSProcessInfo.processInfo, up0 = info.systemUptime, clock = () => info.systemUptime - up0;
  $.NSApplication.sharedApplication.setActivationPolicy(1);   // accessory: no Dock icon, never active
  const windows = new Map();
  let im = null, inAir = 0, playing = false, lastEnd = 0, beat = 0;
  const hideAll = () => transaction(() => { for (const w of windows.values()) w.window.orderOut(null); });
  // One show of `kind` over the display under the pointer, its first rocket LEAD + delay s from now.
  function show(kind, delay) {
    takeEvents();
    const d = pointerDisplay();
    if (!d) { complain("no display"); return; }
    const keys = displayKeys();
    for (const [key, w] of windows) {                          // a display that went away: its window goes too
      if (keys.indexOf(key) >= 0) continue;
      transaction(() => w.window.orderOut(null));
      for (const s of w.shows) inAir -= s.rockets;
      windows.delete(key);
    }
    const W = d.frame.size.width, H = d.frame.size.height;
    const rockets = kind === "finale" ? finale(Math.random, W, H) : salvo(Math.random, W, H);
    if (inAir + rockets.length > MOST) return;                 // the sky is full: this one is dropped
    let w = windows.get(d.key);
    if (!w) { w = makeWindow(d); windows.set(d.key, w); }
    const S = Math.max(2, Math.ceil(d.scale));
    if (!im || im.S < S) im = images(S);
    let length = 0;
    transaction(() => {
      const set = launch(w.root, rockets, $.CACurrentMediaTime(), delay, im, d.scale, W, H);
      w.shows.push({ layers: set.layers, ends: clock() + set.length + 0.3, rockets: rockets.length });
      length = set.length;
      if (!w.shown) { w.window.orderFrontRegardless; w.shown = true; }
    });
    inAir += rockets.length;
    playing = true;
    say("show " + kind + " " + rockets.length + " " + length.toFixed(1));
  }
  say("up");
  for (;;) {
    if ($.getppid() !== parent) { hideAll(); return; }         // the loop is gone: so are the fireworks
    const names = files.contentsOfDirectoryAtPathError(notes, null);
    const n = names.isNil() ? 0 : Number(names.count);
    if (n > 0) {
      const wall = Date.now() / 1000, asked = [];
      for (let i = 0; i < n; i++) {
        const name = ObjC.unwrap(names.objectAtIndex(i));
        files.removeItemAtPathError($(dir + "/shows/" + name), null);
        const when = parseFloat(name), kind = name.slice(name.lastIndexOf(".") + 1);
        if (when > wall - FRESH && when < wall + 2 && (kind === "salvo" || kind === "finale")) asked.push({ when: when, kind: kind });
      }
      asked.sort((a, b) => a.when - b.when);
      asked.slice(0, 4).forEach((a, i) => {
        try { show(a.kind, i * STAGGER); } catch (e) { complain("no show: " + e); }
      });
    }
    // Shows that have burnt out go; a window with none left leaves the screen.
    const now = clock();
    for (const w of windows.values()) {
      if (!w.shows.some(s => s.ends <= now)) continue;
      transaction(() => {
        const keep = [];
        for (const s of w.shows) {
          if (s.ends > now) { keep.push(s); continue; }
          for (const l of s.layers) l.removeFromSuperlayer;
          inAir -= s.rockets;
        }
        w.shows = keep;
        if (!keep.length && w.shown) { w.window.orderOut(null); w.shown = false; }
      });
    }
    const busy = [...windows.values()].some(w => w.shows.length > 0);
    if (playing && !busy) { playing = false; lastEnd = now; say("quiet"); }
    if (now >= beat) { beat = now + 1; say("."); }
    if (!busy && now - lastEnd > rest) { hideAll(); say("bye"); return; }
    delay(POLL);
  }
}

// --- Tool modes ----------------------------------------------------------------------------------------------------

// What one set of layers gives, read back from the emitters themselves: per top-level cell its first particle (s on
// the clock of the layer), how many, how long they live, and its sub-cells (birth rate, window, life).
function readBack(layers) {
  const cells = [];
  for (const e of layers) {
    const list = e.emitterCells;
    for (let i = 0; i < Number(list.count); i++) {
      const c = list.objectAtIndex(i), kids = [], sub = c.emitterCells;
      if (!sub.isNil()) for (let j = 0; j < Number(sub.count); j++) {
        const k = sub.objectAtIndex(j);
        kids.push({ rate: Number(k.birthRate), begin: Number(k.beginTime), dur: Number(k.duration) || Infinity,
                    life: Number(k.lifetime), lr: Number(k.lifetimeRange) });
      }
      const rate = Number(c.birthRate), dur = Number(c.duration);
      cells.push({ start: Number(c.beginTime), rate: rate, dur: dur, n: Math.ceil(rate * dur - 1e-9),
                   life: Number(c.lifetime), lr: Number(c.lifetimeRange), kids: kids });
    }
  }
  return cells;
}

// The share of the particles of a cell still alive at age a (their lives spread evenly over life +- lr/2).
function share(c, a) {
  if (a < 0) return 0;
  if (!(c.lr > 0)) return a < c.life ? 1 : 0;
  return Math.min(1, Math.max(0, (c.life + c.lr / 2 - a) / c.lr));
}

// About how many particles are alive at t: the top-level ones and what their sub-cells have born and not lost.
function alive(cells, t) {
  let sum = 0;
  for (const c of cells) {
    const a = t - c.start;
    if (a < 0) continue;
    sum += c.n * share(c, a);
    for (const k of c.kids) {
      // born from one parent over [from, to] and not yet gone (taking their mean life), while that parent lived
      const from = Math.max(k.begin, a - k.life), to = Math.min(a, k.begin + k.dur, c.life + c.lr / 2);
      if (to > from) sum += c.n * share(c, (from + to) / 2) * k.rate * (to - from);
    }
  }
  return sum;
}

function busiest(cells, length) {
  let most = 0, when = 0;
  for (let t = 0; t <= length; t += 0.02) { const n = alive(cells, t); if (n > most) { most = n; when = t; } }
  return { most: Math.round(most), when: when };
}

// --check: a salvo, a finale and the worst the budget allows (a finale and salvos up to MOST rockets at once), set up
// offscreen exactly as live on a 1440 x 900 pt display, then read back from the emitters.
function check() {
  const W = 1440, H = 900, im = images(2), rand = seeded(20261001), lines = [], problems = [];
  lines.push("drag behaviour: " + (DRAG ? "yes" : "no: the sparks fly at a steady speed"));
  function setUp(shows) {
    const root = $.CALayer.layer, layers = [], each = [];
    root.setFrame($.CGRectMake(0, 0, W, H));
    let length = 0, rockets = 0;
    shows.forEach((list, i) => {
      const set = launch(root, list, 0, i * STAGGER, im, 2, W, H);
      layers.push(...set.layers);
      each.push(...set.each);
      length = Math.max(length, set.length);
      rockets += list.length;
    });
    return { layers: layers, each: each, cells: readBack(layers), length: length, rockets: rockets };
  }
  function describe(name, list) {
    const set = setUp([list]);
    lines.push("");
    lines.push(name + ": " + list.length + " rockets, launches over " + (list[list.length - 1].at - list[0].at).toFixed(1) +
               " s, bursts " + (LEAD + Math.min(...list.map(r => r.at + r.T))).toFixed(1) + "-" +
               (LEAD + Math.max(...list.map(r => r.at + r.T))).toFixed(1) + " s, burnt out at " + set.length.toFixed(1) + " s");
    list.forEach((r, i) => {
      const own = readBack(set.each[i]);
      const head = own[0], flash = own[1], sparks = own.slice(2);
      const lives = sparks.map(c => c.life + c.lr / 2), kids = sparks[0].kids;
      lines.push("  " + (r.kind + "       ").slice(0, 8) + " up " + head.start.toFixed(2) + " s from x " + Math.round(r.x0) +
                 ", burst " + flash.start.toFixed(2) + " s at " + Math.round(r.xb) + "," + Math.round(r.yb) +
                 " (" + Math.round(100 * r.yb / H) + "% up), R " + Math.round(r.R) + " pt, " + r.c1 + "/" + r.c2 +
                 "; head " + head.n + " (life " + head.life.toFixed(2) + ", trail " + head.kids.map(k => k.rate + "/s").join("") +
                 "), flash " + flash.n + ", sparks " + sparks.map(c => c.n).join("+") + " living up to " +
                 Math.max(...lives).toFixed(1) + " s, each " + kids.map(k => k.rate + "/s x " + k.life.toFixed(2) + " s" +
                 (k.dur < Infinity ? " for " + k.dur + " s" : "")).join(" + "));
      if (head.n !== 1 || flash.n !== 1) problems.push(name + " rocket " + (i + 1) + ": head " + head.n + ", flash " + flash.n);
      if (head.start < 0.1 || flash.start < 0.1) problems.push(name + " rocket " + (i + 1) + ": a window opens before the emitter runs");
      if (Math.abs(head.life - (flash.start - head.start)) > 1e-6) problems.push(name + " rocket " + (i + 1) + ": the head does not go out at the burst");
      if (r.yb + r.R > H || r.yb < H * 0.4) problems.push(name + " rocket " + (i + 1) + ": the burst is not in the upper part of the display");
      for (const e of set.each[i]) {                         // a cell after one with sub-cells would be drawn as squares
        const list = e.emitterCells;
        for (let j = 0, parent = false; j < Number(list.count); j++) {
          if (parent) problems.push(name + " rocket " + (i + 1) + ": a cell comes after one with sub-cells in its layer");
          const sub = list.objectAtIndex(j).emitterCells;
          if (!sub.isNil() && Number(sub.count) > 0) parent = true;
        }
      }
    });
    const peak = busiest(set.cells, set.length);
    lines.push("  busiest: about " + peak.most + " particles alive at " + peak.when.toFixed(1) + " s; " +
               set.layers.length + " emitter layers");
    return set;
  }
  describe("salvo (a tap)", salvo(rand, W, H));
  describe("salvo (a tap)", salvo(rand, W, H));
  describe("finale (a long press)", finale(rand, W, H));
  const fin = finale(rand, W, H), shows = [fin];
  for (let n = fin.length; ;) { const s = salvo(rand, W, H); if (n + s.length > MOST) break; shows.push(s); n += s.length; }
  const worst = setUp(shows), peak = busiest(worst.cells, worst.length);
  lines.push("");
  lines.push("worst the budget lets in (a finale and " + (shows.length - 1) + " salvos at once, " + worst.rockets +
             " rockets of at most " + MOST + "): about " + peak.most + " particles alive at " + peak.when.toFixed(1) + " s");
  lines.push(problems.length ? "PROBLEMS:\n  " + problems.join("\n  ") : "ok: one head and one flash per rocket, windows open after the emitters run, " +
             "every burst in the upper part, no cell after one with sub-cells in its layer");
  say(lines.join("\n"));
}

// --preview <out.png>: the particle images (enlarged, white and in every colour, on dark and on light), frames of a
// salvo and of a finale as Core Animation itself renders them (CARenderer into a Metal texture, offscreen: no window)
// at half size, and six close-ups of the salvo at full size (1 px a point: a rocket rising, its burst, a willow, a
// ring). Each frame is laid over a light desktop with a dark window, as the window server lays the overlay over the
// screen.
function preview(args) {
  const file = args[0] || "";
  if (!file) { complain("usage: --preview <out.png>"); return; }
  ObjC.import("Metal");
  ObjC.import("CoreImage");
  ObjC.bindFunction("objc_msgSend", ["void", ["id", "SEL", "double", "void *"]]);   // its CVTimeStamp does not bridge
  const beginFrame = $.NSSelectorFromString($("beginFrameAtTime:timeStamp:"));
  const W = 1440, H = 900, k = 0.5, tw = W * k, th = H * k, gap = 10, strip = 230, im = images(2);
  const device = $.MTLCreateSystemDefaultDevice();
  if (!device || device.isNil()) { complain("no Metal device"); return; }
  let frames = 0, spent = 0;
  // The show rendered from its start; returns the picture at each moment (s from the start of its clock, ascending).
  function film(rockets, moments) {
    const desc = $.MTLTextureDescriptor.texture2DDescriptorWithPixelFormatWidthHeightMipmapped(80, W, H, false);
    desc.setUsage(1 | 4);                                   // read, render target
    const tex = device.newTextureWithDescriptor(desc), queue = device.newCommandQueue;
    const opts = $.NSMutableDictionary.dictionary;
    opts.setObjectForKey(queue, $.kCARendererMetalCommandQueue);
    const renderer = $.CARenderer.rendererWithMTLTextureOptions(tex, opts);
    const root = $.CALayer.layer;
    root.setFrame($.CGRectMake(0, 0, W, H));
    const t0 = $.CACurrentMediaTime() + 1;
    $.CATransaction.begin;
    $.CATransaction.setDisableActions(true);
    launch(root, rockets, t0, 0, im, 2, W, H);
    $.CATransaction.commit;
    $.CATransaction.flush;
    renderer.setLayer(root);
    renderer.setBounds($.CGRectMake(0, 0, W, H));
    $.CATransaction.flush;
    const ciOpts = $.NSMutableDictionary.dictionary;
    ciOpts.setObjectForKey(ObjC.castRefToObject(space), $.kCIImageColorSpace);
    // The renderer draws over what the texture holds: it is cleared to transparent before every frame, as a window is.
    const clear = $.MTLRenderPassDescriptor.renderPassDescriptor, target = clear.colorAttachments.objectAtIndexedSubscript(0);
    target.setTexture(tex);
    target.setLoadAction(2);                                // clear
    target.setStoreAction(1);                               // store
    target.setClearColor($.MTLClearColorMake(0, 0, 0, 0));
    const shots = [];
    for (let f = -6, next = 0; next < moments.length; f++) {
      const t = f / 60, a = Date.now(), wipe = queue.commandBuffer;
      wipe.renderCommandEncoderWithDescriptor(clear).endEncoding;
      wipe.commit;
      $.objc_msgSend(renderer, beginFrame, t0 + t, null);
      renderer.addUpdateRect(renderer.bounds);
      renderer.render;
      renderer.endFrame;
      const done = queue.commandBuffer;
      done.commit; done.waitUntilCompleted;
      spent += Date.now() - a; frames++;
      while (next < moments.length && t + 1e-6 >= moments[next]) {
        shots.push($.NSBitmapImageRep.alloc.initWithCIImage($.CIImage.imageWithMTLTextureOptions(tex, ciOpts)));
        next++;
      }
    }
    return shots;
  }
  const rand = seeded(20261001);
  const first = salvo(rand, W, H), grand = finale(rand, W, H);
  // Close-ups of the salvo at full size: [its rocket, s from its burst (below 0: still rising)], centred on it.
  const byKind = kind => first.find(r => r.kind === kind) || first[first.length - 1];
  const close = [[first[0], -0.45], [first[0], 0.15], [first[0], 0.7], [byKind("willow"), 0.5], [byKind("willow"), 1.6],
                 [byKind("ring"), 0.6]].map(([r, d]) => {
    const f = flight(r), a = r.T + Math.min(0, d);
    const x = d < 0 ? r.x0 + f.speed * Math.cos(f.heading) * a : r.xb;
    const y = d < 0 ? Y0 + f.speed * Math.sin(f.heading) * a - f.g * a * a / 2 : r.yb;
    return { t: LEAD + r.at + r.T + d, label: r.kind + (d < 0 ? " rising" : " " + d.toFixed(2) + " s after its burst") + ", 1:1",
             from: $.CGRectMake(Math.min(W - tw, Math.max(0, x - tw / 2)), Math.min(H - th, Math.max(0, y - th / 2)), tw, th) };
  });
  const salvoAt = [0.7, 1.45, 1.9, 2.6, 3.4, 4.6], finaleAt = [1.4, 3.0, 4.6, 5.9, 6.6, 8.2];
  const both = salvoAt.concat(close.map(c => c.t)).sort((a, b) => a - b), shotsS = film(first, both), shotsF = film(grand, finaleAt);
  const tiles = salvoAt.map(t => ({ shot: shotsS[both.indexOf(t)], label: "salvo " + t.toFixed(1) + " s" }))
    .concat(finaleAt.map((t, i) => ({ shot: shotsF[i], label: "finale " + t.toFixed(1) + " s" })))
    .concat(close.map(c => ({ shot: shotsS[both.indexOf(c.t)], label: "salvo: " + c.label, from: c.from })));
  const cw = 3 * tw + 4 * gap, ch = strip + Math.ceil(tiles.length / 3) * (th + gap) + gap;
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, cw, ch, 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
  const g = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep), ctx = g.CGContext;
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext(g);
  $.CGContextSetRGBFillColor(ctx, 0.08, 0.08, 0.09, 1);
  $.CGContextFillRect(ctx, $.CGRectMake(0, 0, cw, ch));
  const label = $.NSMutableDictionary.dictionary;
  label.setObjectForKey($.NSFont.monospacedDigitSystemFontOfSizeWeight(13, 0), $.NSFontAttributeName);
  label.setObjectForKey($.NSColor.colorWithSRGBRedGreenBlueAlpha(1, 1, 1, 0.85), $.NSForegroundColorAttributeName);
  // The strip: each image at 4x, white, on dark and on light; then a spark in every colour, on dark and on light.
  let x = gap;
  for (const [name, img, pt] of [["spark", im.spark, 14], ["ember", im.ember, 8], ["glow", im.glow, 72]]) {
    const side = Math.min(200, pt * 4);
    for (const light of [false, true]) {
      $.CGContextSetRGBFillColor(ctx, light ? 0.93 : 0.12, light ? 0.93 : 0.12, light ? 0.95 : 0.14, 1);
      $.CGContextFillRect(ctx, $.CGRectMake(x, ch - strip + 10, side, side));
      $.CGContextDrawImage(ctx, $.CGRectMake(x, ch - strip + 10, side, side), img);
      x += side + 6;
    }
    $(name).drawAtPointWithAttributes($.CGPointMake(x - 2 * side - 6, ch - 26), label);
    x += gap;
  }
  NAMES.forEach((name, i) => {
    for (const light of [false, true]) {
      const bx = x + i * 52, by = ch - strip + 10 + (light ? 0 : 60);
      $.CGContextSetRGBFillColor(ctx, light ? 0.93 : 0.12, light ? 0.93 : 0.12, light ? 0.95 : 0.14, 1);
      $.CGContextFillRect(ctx, $.CGRectMake(bx, by, 48, 56));
      $.CGContextSaveGState(ctx);
      $.CGContextClipToMask(ctx, $.CGRectMake(bx, by + 4, 48, 48), im.spark);
      const c = PALETTE[name];
      $.CGContextSetRGBFillColor(ctx, c[0], c[1], c[2], 1);
      $.CGContextFillRect(ctx, $.CGRectMake(bx, by + 4, 48, 48));
      $.CGContextRestoreGState(ctx);
    }
    $(name).drawAtPointWithAttributes($.CGPointMake(x + i * 52, ch - strip + 132), label);
  });
  // The frames.
  tiles.forEach((tile, i) => {
    const ox = gap + (i % 3) * (tw + gap), oy = ch - strip - (Math.floor(i / 3) + 1) * (th + gap);
    $.CGContextSetRGBFillColor(ctx, 0.9, 0.91, 0.94, 1);                         // a light desktop...
    $.CGContextFillRect(ctx, $.CGRectMake(ox, oy, tw, th));
    $.CGContextSetRGBFillColor(ctx, 0.11, 0.12, 0.15, 1);                        // ...with a dark window on it
    $.CGContextFillRect(ctx, $.CGRectMake(ox + tw * 0.04, oy + th * 0.06, tw * 0.6, th * 0.86));
    const picture = $.NSImage.alloc.initWithSize($.CGSizeMake(W, H));
    picture.addRepresentation(tile.shot);
    picture.drawInRectFromRectOperationFraction($.CGRectMake(ox, oy, tw, th), tile.from || $.CGRectMake(0, 0, W, H), 2, 1);   // 2: source over
    $(tile.label).drawAtPointWithAttributes($.CGPointMake(ox + 8, oy + th - 22), label);
  });
  g.flushGraphics;
  $.NSGraphicsContext.restoreGraphicsState;
  const png = rep.representationUsingTypeProperties(4, $.NSDictionary.dictionary);    // 4: PNG
  if (!png.writeToFileAtomically($(file), true)) { complain("cannot write " + file); return; }
  say("preview: " + file + "; " + frames + " frames rendered offscreen at " + W + "x" + H + " px, " +
      (spent / frames).toFixed(1) + " ms each, simulation and drawing, in this process (an indication, not the window server)");
}'

usage() { print -u2 -- "usage: startup.zsh [--check | --preview <out.png>]"; exit 2 }
if (( $# )); then
  case $1 in
    (--check)   (( $# == 1 )) || usage; exec osascript -l JavaScript -e "$overlay_js" -- --check ;;
    (--preview) (( $# == 2 )) || usage; exec osascript -l JavaScript -e "$overlay_js" -- --preview $2 ;;
    (*) usage ;;
  esac
fi
if (( dry == 0 )) && [[ -z ${DESMAPTIC_TOKEN:-} ]]; then
  print -u2 -- "fireworks: not started by Desmaptic Agent (no DESMAPTIC_TOKEN): try FIREWORKS_DRY=1"
  exit 1
fi

opid=""                 # the overlay
post_fd=0 post_pid=0    # a post on its way: the pipe its answer comes back on, and its curl
# stop_overlay [signal]: ends the overlay (TERM; KILL for one that does not answer). Its windows go with it.
stop_overlay() { [[ -n $opid ]] && kill -${1:-TERM} $opid 2>/dev/null; opid="" }
# drop_post: forgets a post on its way and ends its curl.
drop_post() { (( post_pid )) && kill $post_pid 2>/dev/null; (( post_fd )) && exec {post_fd}<&-; post_fd=0 post_pid=0 }
# forget_pid: the pid file goes, unless a newer loop has already written its own.
forget_pid() { local p=""; { IFS= read -r p < $pid_file } 2>/dev/null; [[ $p == $$ ]] && zf_rm -f -- $pid_file 2>/dev/null }
trap 'stop_overlay; drop_post; forget_pid; exit 0' TERM INT HUP
trap 'stop_overlay; drop_post' EXIT

# The overlay, as a coprocess: its lines ("up", "show ...", "quiet", a "." every second, "bye") come back to this loop.
start_overlay() {
  coproc osascript -l JavaScript -e "$overlay_js" -- $dir $keep_alive
  opid=$! began=$EPOCHSECONDS heard=$EPOCHREALTIME said_bye=0
}

# post_start <lit | rest>: sends it to the button without waiting for the answer. curl runs beside this loop (first
# its pid, then the body and the status on the last line come back on post_fd); post_check reads it. The token goes
# from the environment into the request by curl itself, never on a command line.
post_start() {
  local json
  if [[ $1 == lit ]]; then json="{\"cellId\":\"$cell\",\"color\":\"$lit\"}"
  else json="{\"cellId\":\"$cell\",\"reset\":true}"; fi
  if (( dry )); then print -r -- "post: $json"; shown=$1; return 0; fi
  exec {post_fd}< <(print -r -- $sysparams[pid]; exec curl -q -sS --max-time 3 -w '\n%{http_code}\n' \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H 'Content-Type: application/json' --data-binary "$json" http://127.0.0.1:9848/api/update-button 2>&1) ||
    { post_fd=0; return 1 }
  post_pid=0 posting=$1 answer=""
  { IFS= read -r -t 1 -u $post_fd post_pid } 2>/dev/null
  [[ $post_pid == <-> ]] || post_pid=0
}

# post_check: never waits — it takes only the bytes already there (sysread, not a line read that would wait for the
# rest of a line). Once the whole answer is in: shown = what was posted when the agent took it; otherwise the failure
# is reported once and the next try waits 2 s.
post_check() {
  local chunk
  while zselect -t 0 -r $post_fd; do
    if sysread -i $post_fd chunk 2>/dev/null; then answer+=$chunk; continue; fi
    exec {post_fd}<&-                               # the end (or a broken pipe): the post is over
    post_fd=0 post_pid=0
    answer=${answer%$'\n'}
    if [[ ${answer##*$'\n'} == 200 ]]; then shown=$posting failing=0
    else
      (( failing )) || print -u2 -- "fireworks: update-button did not take it: ${${answer//$'\n'/ }[1,200]}"
      failing=1 retry_at=$(( EPOCHSECONDS + 2 ))
    fi
    return
  done
}

zf_mkdir -p -- $shows 2>/dev/null
[[ -d $shows ]] || { print -u2 -- "fireworks: cannot write in $dir"; exit 1 }
stale=( $shows/*(N) )                   # left from before this loop: too late to show
(( $#stale )) && zf_rm -f -- $stale
{ print -r -- $$ > $pid_file } 2>/dev/null || { print -u2 -- "fireworks: cannot write in $dir"; exit 1 }

waits=(5 10 20 40 60)   # after the overlay failed: seconds before the next try
fails=0 start_at=0      # the overlay failed so many times in a row; when to try again
shown=""                # what the button shows: lit, rest; "" not known yet (so the first pass posts rest)
playing=0               # a show plays: the overlay said "show" and not yet "quiet"
pretend=0               # FIREWORKS_DRY=1: when the show it only printed would be over
retry_at=0 failing=0    # after a failed post: when to post again; a failure was reported
odd=0                   # the overlay printed something unexpected (reported once)
last_pass=$EPOCHREALTIME heard=$EPOCHREALTIME
while true; do
  # This loop was not running for a while (stopped, the Mac asleep): it cannot know whether the overlay spoke
  # meanwhile, so it listens again from now instead of calling it stuck.
  (( EPOCHREALTIME - last_pass > 2 )) && heard=$EPOCHREALTIME
  last_pass=$EPOCHREALTIME

  if [[ -z $opid ]]; then
    waiting=( $shows/*(N) )
    if (( $#waiting )); then
      if (( dry == 1 )); then
        for note in $waiting; do print -r -- "show: ${note##*.}"; done
        zf_rm -f -- $waiting
        playing=1 pretend=$(( EPOCHSECONDS + 8 ))
      elif (( EPOCHSECONDS >= start_at )); then
        start_overlay
      else
        zf_rm -f -- $waiting              # the overlay keeps failing: they would show far too late
      fi
    fi
    (( dry == 1 && playing && EPOCHSECONDS >= pretend )) && { playing=0; print -r -- "quiet" }
  fi

  if [[ -n $opid ]]; then
    waited=$EPOCHREALTIME
    if { IFS= read -r -t 0.25 -p line } 2>/dev/null; then
      heard=$EPOCHREALTIME
      case $line in
        (up|.) ;;
        (show\ *) playing=1; (( dry )) && print -r -- $line ;;
        (quiet) playing=0; (( dry )) && print -r -- $line ;;
        (bye) said_bye=1 ;;
        (*) (( odd )) || print -u2 -- "fireworks: the overlay printed something unexpected"; odd=1 ;;
      esac
    elif (( EPOCHREALTIME - waited < 0.2 )); then     # no wait, no line: the overlay is gone
      opid="" playing=0
      if (( said_bye )); then
        fails=0                         # it quit by itself, keep_alive seconds after the last show
      else
        now=$EPOCHSECONDS
        (( now - began >= 60 )) && fails=0
        start_at=$(( now + waits[fails < 5 ? fails + 1 : 5] ))
        print -u2 -- "fireworks: the overlay stopped; it can start again in $(( start_at - now )) s"
        (( fails++ ))
      fi
    elif (( EPOCHREALTIME - waited > 2 )); then       # this wait took far longer than asked: not running either
      heard=$EPOCHREALTIME
    elif (( EPOCHREALTIME - heard > 5 )); then        # it says something every second: silent longer, it is stuck
      print -u2 -- "fireworks: the overlay went quiet; ending it"
      stop_overlay KILL
      playing=0 start_at=$(( EPOCHSECONDS + 5 ))
    fi
  elif (( post_fd )); then
    zselect -t 25 -r $post_fd                         # a quarter of a second, or until the answer comes
  else
    zselect -t 25
  fi

  if (( playing )); then face=lit; else face=rest; fi
  (( post_fd )) && post_check
  if (( ! post_fd )) && [[ $face != "$shown" ]] && (( EPOCHSECONDS >= retry_at )); then post_start $face; fi
done
