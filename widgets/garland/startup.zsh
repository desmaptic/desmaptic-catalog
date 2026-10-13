modes="waves warm twinkle"   # ← a long press steps through these in order: waves (colour waves), warm (warm white), twinkle
minutes=60                   # ← the garland goes out by itself this many minutes after the tap
colours="#FF2D45 #FFC400 #1EE65A #2E7DFF #E040FF"   # ← the bulbs' colours, repeating along the wire (waves, twinkle)
warm="#FFD580"               # ← the colour of every bulb in warm
look="lush"                  # ← lush (two strands, many big bulbs) or slim (one thin strand, fewer and smaller bulbs)
# Garland, the live loop (the button's startup script). The five lines above are yours to edit: drop a mode you do not
# want, change the order (the first one is where a new garland starts), set the timer, pick colours as #RRGGBB, the look.
# Saving the button restarts this script with them.
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/system || { print -u2 -- "garland: zsh modules datetime/zselect/system are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "garland: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
on_file="$dir/on"
go_file="$dir/lit"
mode_file="$dir/mode"
nexts="$dir/next"
pid_file="$dir/loop"
step=1.6
dry=${GARLAND_DRY:-0}
[[ $dry == [012] ]] || dry=0

known=(waves warm twinkle)
list=()
for m in ${=modes}; do
  if (( ${known[(Ie)$m]} )); then list+=($m); else print -u2 -- "garland: skipped the mode \"$m\": the modes are $known"; fi
done
(( $#list )) || list=(waves)
if [[ $minutes != (<->|<->.<->) ]] || (( minutes <= 0 )); then
  print -u2 -- "garland: minutes must be a number above 0; using 60"
  minutes=60
fi
bulbs=()
for c in ${=colours}; do
  if [[ ${#c} == 7 && $c == \#* && ${c:1} != *[^0-9A-Fa-f]* ]]; then bulbs+=($c)
  else print -u2 -- "garland: skipped the colour \"$c\": write it as #RRGGBB"; fi
done
(( $#bulbs )) || bulbs=("#FF2D45" "#FFC400" "#1EE65A" "#2E7DFF" "#E040FF")
if [[ ${#warm} != 7 || $warm != \#* || ${warm:1} == *[^0-9A-Fa-f]* ]]; then
  print -u2 -- "garland: skipped the warm colour \"$warm\": write it as #RRGGBB"
  warm="#FFD580"
fi
if [[ $look != (lush|slim) ]]; then
  print -u2 -- "garland: skipped the look \"$look\": the looks are lush slim; using lush"
  look=lush
fi

garland_js='ObjC.import("AppKit");
ObjC.import("QuartzCore");
ObjC.import("CoreGraphics");
ObjC.bindFunction("getppid", ["int", []]);

const LOOKS = {
  slim: { span: 170, strands: [[11, 0, 5]], hang: 5.5, bulb: [5, 7.5], glass: 12, light: 40, glow: 5, strip: 40, wire: 1.1 },
  lush: { span: 150, strands: [[22, 0, 7], [15, 0.5, 6]], hang: 7, bulb: [7.5, 11], glass: 18, light: 52, glow: 9,
          strip: 60, wire: 1.7 }
};
const TOP = 1.5;
let SPAN, STRANDS, HANG, BULB_W, BULB_H, GLASS, LIGHT, GLOW, STRIP, WIRE;
const START = 1000;
const FADE_IN = 1.2, FADE_OUT = 2, SWAP = 0.8;
const WAVE = 2.6;
const LENGTH = 560;
const DIM = 0.1;
const MODES = ["waves", "warm", "twinkle"];

const space = $.CGColorSpaceCreateWithName($.kCGColorSpaceSRGB);
const out = $.NSFileHandle.fileHandleWithStandardOutput;
const err = $.NSFileHandle.fileHandleWithStandardError;

function say(text) { out.writeData($(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function complain(text) { err.writeData($("garland: " + text + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function number(x) { return $.NSNumber.numberWithDouble(x); }
function isHex(h) { return /^#[0-9A-Fa-f]{6}$/.test(h); }
function rgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255]; }
function mix(c, d, k) { return c.map((v, i) => v + (d[i] - v) * k); }
function colour(c, a) { return $.CGColorCreateSRGB(c[0], c[1], c[2], a); }
const WHITE = [1, 1, 1], BLACK = [0, 0, 0];

function bitmap(w, h, draw) {
  const ctx = $.CGBitmapContextCreate(null, w, h, 8, 0, space, 1);
  draw(ctx);
  return $.CGBitmapContextCreateImage(ctx);
}

function ellipse(ctx, x, y, rx, ry, fill) {
  $.CGContextSetFillColorWithColor(ctx, fill);
  $.CGContextFillEllipseInRect(ctx, $.CGRectMake(x - rx, y - ry, 2 * rx, 2 * ry));
}

function useLook(name) {
  const l = LOOKS[name] || LOOKS.lush;
  SPAN = l.span; STRANDS = l.strands; HANG = l.hang; BULB_W = l.bulb[0]; BULB_H = l.bulb[1];
  GLASS = l.glass; LIGHT = l.light; GLOW = l.glow; STRIP = l.strip; WIRE = l.wire;
}

function glassImage(c, S) {
  const side = Math.ceil(GLASS * S), m = side / 2, rx = BULB_W / 2 * S, ry = BULB_H / 2 * S;
  return bitmap(side, side, ctx => {
    ellipse(ctx, m, m, rx + 0.5 * S, ry + 0.5 * S, colour(BLACK, 0.3));
    ellipse(ctx, m, m, rx, ry, colour(mix(c, BLACK, 0.2), 0.9));
    ellipse(ctx, m - rx * 0.3, m + ry * 0.25, rx * 0.28, ry * 0.3, colour(WHITE, 0.4));
  });
}

function lightImage(c, S) {
  const side = Math.ceil(LIGHT * S), m = side / 2, rx = BULB_W / 2 * S, ry = BULB_H / 2 * S, away = 4 * side;
  return bitmap(side, side, ctx => {
    for (const [blur, size, alpha] of [[1.6, 2, 0.8], [0.7, 1.5, 1]]) {
      $.CGContextSaveGState(ctx);
      $.CGContextSetShadowWithColor(ctx, $.CGSizeMake(away, 0), GLOW * blur * S, colour(c, alpha));
      ellipse(ctx, m - away, m, rx * size, ry * size * 0.85, colour(c, 1));
      $.CGContextRestoreGState(ctx);
    }
    ellipse(ctx, m, m, rx, ry, colour(mix(c, WHITE, 0.3), 1));
    ellipse(ctx, m, m - ry * 0.1, rx * 0.6, ry * 0.6, colour(mix(c, WHITE, 0.8), 1));
  });
}

function images(S, colours, warm) {
  const im = { S: S, colours: colours, warm: warm, glass: {}, light: {} };
  for (const h of colours.concat([warm])) {
    if (im.glass[h]) continue;
    im.glass[h] = glassImage(rgb(h), S);
    im.light[h] = lightImage(rgb(h), S);
  }
  return im;
}

function wireY(x, span, s) { const t = x / span - s[1] - Math.floor(x / span - s[1]); return STRIP - TOP - s[0] * 4 * t * (1 - t); }

function layout(W) {
  const n = Math.max(1, Math.round(W / SPAN)), span = W / n, bulbs = [];
  for (const s of STRANDS) for (let k = -1; k <= n; k++) for (let j = 0; j < s[2]; j++) {
    const x = (k + s[1] + (j + 0.5) / s[2]) * span;
    if (x < 0 || x >= W) continue;
    bulbs.push({ x: x, wy: wireY(x, span, s), y: wireY(x, span, s) - HANG });
  }
  bulbs.sort((a, b) => a.x - b.x);
  return { n: n, span: span, bulbs: bulbs };
}

function wireImage(W, lay, S) {
  return bitmap(Math.ceil(W * S), Math.ceil(STRIP * S), ctx => {
    $.CGContextSetLineCap(ctx, 1);
    $.CGContextSetLineJoin(ctx, 1);
    const steps = lay.n * 24;
    function line(s, width, c) {
      for (let i = 0; i <= steps; i++) {
        const x = i / steps * W, y = wireY(x, lay.span, s);
        if (i === 0) $.CGContextMoveToPoint(ctx, x * S, y * S);
        else $.CGContextAddLineToPoint(ctx, x * S, y * S);
      }
      $.CGContextSetStrokeColorWithColor(ctx, c);
      $.CGContextSetLineWidth(ctx, width * S);
      $.CGContextStrokePath(ctx);
    }
    const dark = colour([0.1, 0.16, 0.12], 1);
    for (const s of STRANDS) {
      line(s, WIRE + 1.3, colour(WHITE, 0.22));
      line(s, WIRE, colour([0.13, 0.2, 0.15], 0.95));
      for (let k = -1; k <= lay.n + 1; k++) {
        const x = (k + s[1]) * lay.span;
        if (x >= 0 && x <= W) ellipse(ctx, x * S, (STRIP - TOP) * S, (WIRE + 0.2) * S, (WIRE + 0.2) * S, dark);
      }
    }
    $.CGContextSetFillColorWithColor(ctx, dark);
    for (const b of lay.bulbs) {
      const top = b.y + BULB_H / 2 - 0.6;
      $.CGContextFillRect(ctx, $.CGRectMake((b.x - BULB_W * 0.28) * S, top * S, BULB_W * 0.56 * S, (b.wy - top + 0.4) * S));
    }
  });
}

function animation(key) { return $.CAKeyframeAnimation.animationWithKeyPath(key); }

function applyMode(p, mode, t, im, swap) {
  const ease = $.CAMediaTimingFunction.functionWithName($.kCAMediaTimingFunctionEaseInEaseOut);
  for (const b of p.bulbs) {
    const h = mode === "warm" ? im.warm : im.colours[b.i % im.colours.length];
    for (const [layer, img] of [[b.glass, im.glass[h]], [b.light, im.light[h]]]) {
      const next = ObjC.castRefToObject(img);
      if (swap) {
        const fade = $.CABasicAnimation.animationWithKeyPath("contents");
        fade.setFromValue(layer.contents);
        fade.setToValue(next);
        fade.setBeginTime(t);
        fade.setDuration(SWAP);
        layer.addAnimationForKey(fade, "swap");
      }
      layer.setContents(next);
    }
    let values, times, d, phase;
    if (mode === "warm") {
      values = [0.85, 1, 0.85]; times = [0, 0.5, 1]; d = 3 + 2 * Math.random(); phase = Math.random();
    } else if (mode === "twinkle") {
      const on = 0.15 + 0.3 * Math.random();
      values = [DIM, 1, 1, DIM, DIM]; times = [0, 0.08, 0.08 + on, 0.16 + on, 1];
      d = 1.2 + 2.2 * Math.random(); phase = Math.random();
    } else {
      values = [DIM, DIM, 1, 1, DIM]; times = [0, 0.26, 0.46, 0.6, 1]; d = WAVE;
      phase = 1 - (b.gx / LENGTH) % 1;
    }
    const blink = animation("opacity");
    blink.setValues($(values.map(number)));
    blink.setKeyTimes($(times.map(number)));
    blink.setTimingFunctions($(values.slice(1).map(() => ease)));
    blink.setDuration(d);
    blink.setRepeatCount(Infinity);
    blink.setBeginTime(t - phase * d);
    b.light.setOpacity(values[0]);
    b.light.addAnimationForKey(blink, "blink");
  }
}

function makeLayers(W, x0, im, mode, t) {
  const root = $.CALayer.layer, wire = $.CALayer.layer, lay = layout(W), S = im.S;
  root.setFrame($.CGRectMake(0, 0, W, STRIP));
  root.setSpeed(0);
  root.setTimeOffset(t);
  wire.setFrame($.CGRectMake(0, 0, W, STRIP));
  wire.setContents(ObjC.castRefToObject(wireImage(W, lay, S)));
  wire.setContentsScale(S);
  root.addSublayer(wire);
  const part = { root: root, bulbs: [] };
  lay.bulbs.forEach((b, i) => {
    const glass = $.CALayer.layer, light = $.CALayer.layer;
    glass.setFrame($.CGRectMake(b.x - GLASS / 2, b.y - GLASS / 2, GLASS, GLASS));
    light.setFrame($.CGRectMake(b.x - LIGHT / 2, b.y - LIGHT / 2, LIGHT, LIGHT));
    for (const l of [glass, light]) { l.setContentsScale(S); root.addSublayer(l); }
    part.bulbs.push({ i: i, gx: x0 + b.x, glass: glass, light: light });
  });
  applyMode(part, mode, t, im, false);
  return part;
}

function setLit(p, lit, t) {
  const fade = $.CABasicAnimation.animationWithKeyPath("opacity"), shown = p.root.presentationLayer;
  fade.setFromValue(number(shown.isNil() ? Number(p.root.opacity) : Number(shown.opacity)));
  fade.setToValue(number(lit ? 1 : 0));
  fade.setBeginTime(t);
  fade.setDuration(lit ? FADE_IN : FADE_OUT);
  const curve = lit ? $.kCAMediaTimingFunctionEaseOut : $.kCAMediaTimingFunctionEaseIn;
  fade.setTimingFunction($.CAMediaTimingFunction.functionWithName(curve));
  p.root.setOpacity(lit ? 1 : 0);
  p.root.addAnimationForKey(fade, "fade");
}

function stripOf(screen) {
  const f = screen.frame, v = screen.visibleFrame;
  const top = Math.min(f.origin.y + f.size.height, v.origin.y + v.size.height);
  return $.CGRectMake(f.origin.x, top - STRIP, f.size.width, STRIP);
}

function makeScreen(screen, x0, im, mode, t) {
  const box = stripOf(screen);
  const w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(box, 0, 2, false);
  w.setOpaque(false);
  w.setBackgroundColor($.NSColor.clearColor);
  w.setHasShadow(false);
  w.setIgnoresMouseEvents(true);
  w.setReleasedWhenClosed(false);
  w.setLevel(23);
  w.setCollectionBehavior(1 | 16 | 64 | 256);
  const view = w.contentView;
  view.setWantsLayer(true);
  const part = makeLayers(box.size.width, x0, im, mode, t);
  part.root.setOpacity(0);
  view.layer.addSublayer(part.root);
  w.orderFrontRegardless;
  part.window = w;
  return part;
}

function displays() {
  const screens = $.NSScreen.screens, list = [];
  for (let i = 0; i < Number(screens.count); i++) {
    const s = screens.objectAtIndex(i), f = stripOf(s);
    list.push([f.origin.x, f.origin.y, f.size.width, f.size.height, s.backingScaleFactor].join(" "));
  }
  return list.join(",");
}

function build(im, mode, t, lit) {
  const screens = $.NSScreen.screens, count = Number(screens.count), parts = [];
  let left = Infinity;
  for (let i = 0; i < count; i++) left = Math.min(left, Number(screens.objectAtIndex(i).frame.origin.x));
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  for (let i = 0; i < count; i++) {
    const s = screens.objectAtIndex(i);
    try { parts.push(makeScreen(s, Number(s.frame.origin.x) - left, im, mode, t)); }
    catch (e) { complain("no garland on display " + (i + 1) + ": " + e); }
  }
  if (lit) for (const p of parts) setLit(p, true, t);
  $.CATransaction.commit;
  $.CATransaction.flush;
  return parts;
}

function sharpest() {
  const screens = $.NSScreen.screens;
  let S = 2;
  for (let i = 0; i < Number(screens.count); i++) S = Math.max(S, Number(screens.objectAtIndex(i).backingScaleFactor));
  return S;
}

function change(parts, act) {
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  for (const p of parts) act(p);
  $.CATransaction.commit;
  $.CATransaction.flush;
}

function clockTo(parts, t, running) {
  change(parts, p => {
    if (running) { p.root.setSpeed(1); p.root.setTimeOffset(t - $.CACurrentMediaTime()); }
    else { p.root.setSpeed(0); p.root.setTimeOffset(t); }
  });
}

function takeDown(parts) { change(parts, p => p.window.orderOut(null)); }

function takeEvents() {
  const app = $.NSApplication.sharedApplication;
  for (let i = 0; i < 64; i++) {
    const e = app.nextEventMatchingMaskUntilDateInModeDequeue($.NSEventMaskAny, $.NSDate.distantPast,
      $.NSDefaultRunLoopMode, true);
    if (e.isNil()) break;
  }
}

function hidden() {
  try {
    const session = ObjC.castRefToObject($.CGSessionCopyCurrentDictionary());
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

function readMode(file, was) {
  const s = $.NSString.stringWithContentsOfFileEncodingError($(file), $.NSUTF8StringEncoding, null);
  const m = s.isNil() ? "" : s.js.trim();
  return MODES.includes(m) ? m : was;
}

function palette(args) {
  const colours = (args[0] || "").split(" ").filter(isHex);
  return { colours: colours.length ? colours : ["#FF2D45", "#FFC400", "#1EE65A", "#2E7DFF", "#E040FF"],
           warm: isHex(args[1] || "") ? args[1] : "#FFD580" };
}

function run(argv) {
  if (argv[0] === "--preview") return preview(argv.slice(1));
  if (argv[0] === "--layout") return measure(argv.slice(1));
  const go = argv[0] || "", modeFile = argv[1] || "", files = $.NSFileManager.defaultManager, parent = $.getppid();
  const wanted = () => files.fileExistsAtPath($(go));
  if (!go || !modeFile || !wanted()) return;
  useLook(argv[4]);
  $.NSApplication.sharedApplication.setActivationPolicy(1);
  const pal = palette(argv.slice(2)), im = images(sharpest(), pal.colours, pal.warm);
  const info = $.NSProcessInfo.processInfo, up0 = info.systemUptime, clock = () => info.systemUptime - up0;
  let mode = readMode(modeFile, "waves"), parts = build(im, mode, START, true), screens = displays();
  let lit = true, fadeEnds = 0, lights = START, last = 0, seen = true, look = 0.5, beat = 1, survey = 2;
  if (!parts.length) { complain("no display to hang the garland on"); return; }
  clockTo(parts, lights, true);
  try { say("up"); } catch (e) { takeDown(parts); return; }
  for (;;) {
    const t = clock();
    if (seen) lights += t - last;
    last = t;
    if (t >= look) {
      look = t + 0.5;
      if ($.getppid() !== parent) { takeDown(parts); return; }
      const was = seen;
      seen = !hidden();
      if (seen !== was) clockTo(parts, lights, seen);
      const want = wanted();
      if (lit && !want) { change(parts, p => setLit(p, false, lights)); lit = false; fadeEnds = t + FADE_OUT; }
      else if (!lit && want) {
        change(parts, p => setLit(p, true, lights));
        lit = true;
        try { say("up"); } catch (e) { takeDown(parts); return; }
      }
      else if (!lit && t >= fadeEnds) { takeDown(parts); try { say("bye"); } catch (e) {} return; }
      const now = readMode(modeFile, mode);
      if (now !== mode) { mode = now; change(parts, p => applyMode(p, mode, lights, im, true)); }
      if (t >= beat) {
        beat = t + 1;
        try { say("."); } catch (e) { takeDown(parts); return; }
      }
      if (lit && t >= survey) {
        survey = t + 2;
        takeEvents();
        const latest = displays();
        if (latest !== screens) {
          takeDown(parts);
          parts = build(im, mode, lights, true);
          clockTo(parts, lights, seen);
          screens = latest;
        }
      }
    }
    delay(Math.max(0.005, look - clock()));
  }
}

function measure(args) {
  useLook(args[0]);
  const W = Number(args[1]) || 1512, lay = layout(W);
  say("bulbs " + lay.bulbs.length + " strands " + STRANDS.length + " strip " + STRIP + " light " + LIGHT);
}

function preview(args) {
  const file = args[0] || "";
  if (!file) { complain("usage: --preview <out.png> <colours> <warm> <look>"); return; }
  useLook(args[3]);
  ObjC.import("Metal");
  ObjC.import("CoreImage");
  ObjC.bindFunction("objc_msgSend", ["void", ["id", "SEL", "double", "void *"]]);
  const beginFrame = $.NSSelectorFromString($("beginFrameAtTime:timeStamp:"));
  const pal = palette(args.slice(1)), S = 2, W = 900, im = images(S, pal.colours, pal.warm);
  const device = $.MTLCreateSystemDefaultDevice();
  if (!device || device.isNil()) { complain("no Metal device"); return; }
  const pw = W * S, ph = STRIP * S;
  const desc = $.MTLTextureDescriptor.texture2DDescriptorWithPixelFormatWidthHeightMipmapped(80, pw, ph, false);
  desc.setUsage(1 | 4);
  const tex = device.newTextureWithDescriptor(desc), queue = device.newCommandQueue;
  const opts = $.NSMutableDictionary.dictionary;
  opts.setObjectForKey(queue, $.kCARendererMetalCommandQueue);
  const renderer = $.CARenderer.rendererWithMTLTextureOptions(tex, opts);
  const top = $.CALayer.layer, holder = $.CALayer.layer;
  top.setFrame($.CGRectMake(0, 0, pw, ph));
  holder.setAnchorPoint($.CGPointMake(0, 0));
  holder.setBounds($.CGRectMake(0, 0, W, STRIP));
  holder.setPosition($.CGPointMake(0, 0));
  holder.setAffineTransform($.CGAffineTransformMakeScale(S, S));
  top.addSublayer(holder);
  renderer.setLayer(top);
  renderer.setBounds($.CGRectMake(0, 0, pw, ph));
  const ciOpts = $.NSMutableDictionary.dictionary;
  ciOpts.setObjectForKey(ObjC.castRefToObject(space), $.kCIImageColorSpace);
  const clear = $.MTLRenderPassDescriptor.renderPassDescriptor, target = clear.colorAttachments.objectAtIndexedSubscript(0);
  target.setTexture(tex);
  target.setLoadAction(2);
  target.setStoreAction(1);
  target.setClearColor($.MTLClearColorMake(0, 0, 0, 0));
  const shots = [];
  for (const [mode, at] of [["waves", 0.4], ["waves", 1.6], ["warm", 1], ["twinkle", 0.7], ["twinkle", 2.2]]) {
    $.CATransaction.begin;
    $.CATransaction.setDisableActions(true);
    const part = makeLayers(W, 0, im, mode, START);
    part.root.setTimeOffset(START + at);
    holder.setSublayers($([part.root]));
    $.CATransaction.commit;
    $.CATransaction.flush;
    const wipe = queue.commandBuffer;
    wipe.renderCommandEncoderWithDescriptor(clear).endEncoding;
    wipe.commit;
    $.objc_msgSend(renderer, beginFrame, $.CACurrentMediaTime(), null);
    renderer.addUpdateRect(renderer.bounds);
    renderer.render;
    renderer.endFrame;
    const done = queue.commandBuffer;
    done.commit; done.waitUntilCompleted;
    shots.push({ rep: $.NSBitmapImageRep.alloc.initWithCIImage($.CIImage.imageWithMTLTextureOptions(tex, ciOpts)),
                 label: (LOOKS[args[3]] ? args[3] : "lush") + " · " + mode + " " + at.toFixed(1) + " s" });
  }
  const bar = 24, row = bar + STRIP + 14, gap = 10, cw = (2 * W + 3 * gap) * S, ch = (shots.length * (row + gap) + gap) * S;
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, cw, ch, 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
  const g = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep), ctx = g.CGContext;
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext(g);
  $.CGContextScaleCTM(ctx, S, S);
  $.CGContextSetRGBFillColor(ctx, 0.08, 0.08, 0.09, 1);
  $.CGContextFillRect(ctx, $.CGRectMake(0, 0, cw, ch));
  const label = $.NSMutableDictionary.dictionary;
  label.setObjectForKey($.NSFont.monospacedDigitSystemFontOfSizeWeight(11, 0), $.NSFontAttributeName);
  shots.forEach((shot, i) => {
    const oy = ch / S - (i + 1) * (row + gap);
    [false, true].forEach((dark, k) => {
      const ox = gap + k * (W + gap), desk = dark ? 0.16 : 0.86, menu = dark ? 0.22 : 0.95;
      $.CGContextSetRGBFillColor(ctx, desk, desk, desk + 0.03, 1);
      $.CGContextFillRect(ctx, $.CGRectMake(ox, oy, W, row));
      $.CGContextSetRGBFillColor(ctx, dark ? 0.1 : 1, dark ? 0.1 : 1, dark ? 0.12 : 1, 1);
      $.CGContextFillRect(ctx, $.CGRectMake(ox + W * 0.45, oy, W * 0.4, row - bar - 6));
      $.CGContextSetRGBFillColor(ctx, menu, menu, menu, 1);
      $.CGContextFillRect(ctx, $.CGRectMake(ox, oy + row - bar, W, bar));
      const picture = $.NSImage.alloc.initWithSize($.CGSizeMake(W, STRIP));
      picture.addRepresentation(shot.rep);
      picture.drawInRectFromRectOperationFraction($.CGRectMake(ox, oy + row - bar - STRIP, W, STRIP),
        $.CGRectMake(0, 0, W, STRIP), 2, 1);
      const ink = dark ? 0.9 : 0.15;
      label.setObjectForKey($.NSColor.colorWithSRGBRedGreenBlueAlpha(ink, ink, ink, 1), $.NSForegroundColorAttributeName);
      $(shot.label).drawAtPointWithAttributes($.CGPointMake(ox + 8, oy + row - bar + 5), label);
    });
  });
  g.flushGraphics;
  $.NSGraphicsContext.restoreGraphicsState;
  const png = rep.representationUsingTypeProperties(4, $.NSDictionary.dictionary);
  if (!png.writeToFileAtomically($(file), true)) { complain("cannot write " + file); return; }
  say("preview: " + file);
}'

if [[ $look == slim ]]; then
  face_x=(32.8 66.4 100 133.6 167.2)
  face_y=(81.44 107.36 116 107.36 81.44)
  face_size=(9.5 13 10 9 20 30)
  face_wires='<path id="wire" d="M16 62 Q100 170 184 62" fill="none" stroke="#8FA898" stroke-width="3.5" stroke-linecap="round"/><circle id="hookL" cx="16" cy="62" r="4.5" fill="#8FA898"/><circle id="hookR" cx="184" cy="62" r="4.5" fill="#8FA898"/>'
else
  face_x=(20 40 60 80 100 120 140 160 180)
  face_y=(67 90.4 103 61.6 115 61.6 103 90.4 67)
  face_size=(8.5 12 9 8 18 34)
  face_wires='<path id="wireB" d="M0 100 Q50 100 100 40 Q150 100 200 100" fill="none" stroke="#8FA898" stroke-width="4" stroke-linecap="round"/><path id="wireA" d="M0 40 Q100 190 200 40" fill="none" stroke="#8FA898" stroke-width="4" stroke-linecap="round"/><circle id="hook" cx="100" cy="40" r="5" fill="#8FA898"/>'
fi
wave=(1 0.5 0.1 0.1 0.5)
face() {
  local mode=$1 c defs="" glows="" body=""
  local -i n=$2 lit=$3 i r
  local -F x y l rx=$face_size[1] ry=$face_size[2] cw=$face_size[3] ch=$face_size[4] drop=$face_size[5] glow=$face_size[6]
  for (( i = 1; i <= $#face_x; i++ )); do
    if [[ $mode == warm ]]; then c=$warm; else (( r = (i - 1) % $#bulbs + 1 )); c=$bulbs[r]; fi
    if (( ! lit )); then l=0
    elif [[ $mode == warm ]]; then (( l = (n + i) % 2 ? 0.85 : 1 ))
    elif [[ $mode == twinkle ]]; then (( r = (n * 7919 + i * 104729) * 2654435761 % 1000, l = r > 420 ? 1 : 0.1 ))
    else (( r = ((i - 1 - n) % 5 + 5) % 5 + 1 )); l=$wave[r]; fi
    x=$face_x[i] y=$face_y[i]
    printf -v defs '%s<radialGradient id="g%d"><stop offset="0" stop-color="%s" stop-opacity="0.95"/><stop offset="0.4" stop-color="%s" stop-opacity="0.55"/><stop offset="1" stop-color="%s" stop-opacity="0"/></radialGradient>' \
      "$defs" $i $c $c $c
    printf -v glows '%s<circle id="glow%d" cx="%.1f" cy="%.1f" r="%.0f" fill="url(#g%d)" opacity="%.2f"/>' \
      "$glows" $i $x $(( y + drop + 1 )) $glow $i $l
    printf -v body '%s<rect id="cap%d" x="%.1f" y="%.1f" width="%.0f" height="%.0f" rx="2" fill="#2E3B32"/><ellipse id="bulb%d" cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s" fill-opacity="%.2f" stroke="#000000" stroke-opacity="0.25" stroke-width="1.5"/><ellipse id="glint%d" cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#FFFFFF" opacity="%.2f"/>' \
      "$body" $i $(( x - cw / 2 )) $(( y - 1 )) $cw $ch $i $x $(( y + drop )) $rx $ry $c $(( 0.4 + 0.6 * l )) \
      $i $(( x - rx * 0.32 )) $(( y + drop - ry * 0.38 )) $(( rx * 0.28 )) $(( ry * 0.3 )) $(( 0.2 + 0.55 * l ))
  done
  REPLY="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>$defs</defs>$face_wires$glows$body</svg>"
}

usage() { print -u2 -- "usage: startup.zsh [--face <rest|demo> <out.svg> | --preview <out.png> | --layout <width>]"; exit 2 }
if (( $# )); then
  case $1 in
    (--face)
      (( $# == 3 )) && [[ $2 == (rest|demo) ]] || usage
      if [[ $2 == rest ]]; then face waves 0 0; else face waves 1 1; fi
      { print -rn -- $REPLY > $3 } 2>/dev/null || { print -u2 -- "garland: cannot write $3"; exit 1 }
      exit 0 ;;
    (--preview)
      (( $# == 2 )) || usage
      exec osascript -l JavaScript -e "$garland_js" -- --preview $2 "$bulbs" $warm $look ;;
    (--layout)
      (( $# == 2 )) && [[ $2 == <1-99999> ]] || usage
      exec osascript -l JavaScript -e "$garland_js" -- --layout $look $2 ;;
    (*) usage ;;
  esac
fi
if (( dry == 0 )) && [[ -z ${DESMAPTIC_TOKEN:-} ]]; then
  print -u2 -- "garland: not started by Desmaptic Agent (no DESMAPTIC_TOKEN): try GARLAND_DRY=1"
  exit 1
fi

opid=""
post_fd=0 post_pid=0
stop_overlay() { [[ -n $opid ]] && kill -${1:-TERM} $opid 2>/dev/null; opid="" }
drop_post() { (( post_pid )) && kill $post_pid 2>/dev/null; (( post_fd )) && exec {post_fd}<&-; post_fd=0 post_pid=0 }
forget_pid() { local p=""; { IFS= read -r p < $pid_file } 2>/dev/null; [[ $p == $$ ]] && zf_rm -f -- $pid_file 2>/dev/null }
trap 'stop_overlay; drop_post; forget_pid; zf_rm -f -- $go_file; exit 0' TERM INT HUP
trap 'stop_overlay; drop_post' EXIT

lit_since() {
  local line=""
  REPLY=""
  { IFS= read -r line < $on_file } 2>/dev/null || return 1
  if [[ $line == <-> ]] && (( ${#line} <= 12 && line <= EPOCHSECONDS + 5 && EPOCHREALTIME < line + minutes * 60 )); then
    REPLY=$line
    return 0
  fi
  zf_rm -f -- $on_file 2>/dev/null
  timed_out=1
  return 1
}

keep_mode() {
  { print -r -- $list[idx] > $mode_file.$$ } 2>/dev/null && zf_mv -f -- $mode_file.$$ $mode_file 2>/dev/null ||
    { zf_rm -f -- $mode_file.$$ 2>/dev/null; print -u2 -- "garland: cannot write in $dir"; return 1 }
}

start_overlay() {
  coproc osascript -l JavaScript -e "$garland_js" -- $go_file $mode_file "$bulbs" $warm $look
  opid=$! began=$EPOCHSECONDS heard=$EPOCHREALTIME said_bye=0
}

post() {
  local s=$1 json
  s=${s//\\/\\\\} s=${s//\"/\\\"}
  json="{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$s\",\"duration\":$2,\"easing\":\"easeInOut\"}}"
  posting=$3
  if (( dry )); then print -r -- "frame: $json"; shown=$posting; return 0; fi
  exec {post_fd}< <(print -r -- $sysparams[pid]; exec curl -q -sS --max-time 3 -w '\n%{http_code}\n' \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H 'Content-Type: application/json' --data-binary "$json" http://127.0.0.1:9848/api/update-button 2>&1) ||
    { post_fd=0; return 1 }
  post_pid=0 answer=""
  { IFS= read -r -t 1 -u $post_fd post_pid } 2>/dev/null
  [[ $post_pid == <-> ]] || post_pid=0
}

post_check() {
  local chunk
  while zselect -t 0 -r $post_fd; do
    if sysread -i $post_fd chunk 2>/dev/null; then answer+=$chunk; continue; fi
    exec {post_fd}<&-
    post_fd=0 post_pid=0
    answer=${answer%$'\n'}
    if [[ ${answer##*$'\n'} == 200 ]]; then
      shown=$posting failing=0
      if [[ ${answer//[[:space:]]/} == *'"visible":false'* ]]; then seen=0; else seen=1; fi
    else
      (( failing )) || print -u2 -- "garland: update-button did not take the face: ${${answer//$'\n'/ }[1,200]}"
      failing=1 retry_at=$(( EPOCHSECONDS + 2 ))
    fi
    return
  done
}

zf_mkdir -p -- $nexts 2>/dev/null
[[ -d $nexts ]] || { print -u2 -- "garland: cannot write in $dir"; exit 1 }
stale=( $nexts/*(N) )
(( $#stale )) && zf_rm -f -- $stale
zf_rm -f -- $go_file 2>/dev/null
idx=1 kept=""
{ IFS= read -r kept < $mode_file } 2>/dev/null
for (( i = 1; i <= $#list; i++ )); do [[ $list[i] == "$kept" ]] && { idx=$i; break }; done
keep_mode || exit 1
{ print -r -- $$ > $pid_file } 2>/dev/null || { print -u2 -- "garland: cannot write in $dir"; exit 1 }
(( dry )) && print -r -- "look: $look" && print -r -- "mode: $list[idx]"

waits=(5 10 20 40 60)
shown=""
up=0
fails=0 start_at=0
stop_by=0
retry_at=0 failing=0
odd=0
was_on=0 timed_out=0
frame=0 next_frame=0
seen=1
peek_until=0
last_pass=$EPOCHREALTIME
while true; do
  now=$EPOCHSECONDS
  (( EPOCHREALTIME - last_pass > 2 )) && heard=$EPOCHREALTIME
  last_pass=$EPOCHREALTIME

  presses=( $nexts/*(N) )
  if (( $#presses )); then
    zf_rm -f -- $presses
    idx=$(( (idx - 1 + $#presses) % $#list + 1 ))
    keep_mode
    (( dry )) && print -r -- "mode: $list[idx]"
    peek_until=$(( EPOCHREALTIME + 2 * step )) next_frame=0
  fi

  timed_out=0
  if lit_since; then want=1; else want=0; fi
  if (( want != was_on )); then
    if (( ! dry )); then :
    elif (( want )); then print -r -- "on"
    elif (( timed_out )); then print -r -- "off: timer"
    else print -r -- "off: tap"; fi
    was_on=$want
  fi
  if (( want )); then
    stop_by=0
    [[ -e $go_file ]] || { : >> $go_file } 2>/dev/null
    if (( dry == 1 )); then up=1
    elif [[ -z $opid ]] && (( now >= start_at )); then start_overlay; fi
  else
    up=0 fails=0 start_at=0
    [[ -e $go_file ]] && zf_rm -f -- $go_file
    if [[ -n $opid ]]; then
      (( stop_by )) || stop_by=$(( now + 10 ))
      (( now >= stop_by )) && { print -u2 -- "garland: the overlay did not stop by itself; ended"; stop_overlay KILL }
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
        (*) (( odd )) || print -u2 -- "garland: the overlay printed something unexpected"; odd=1 ;;
      esac
    elif (( EPOCHREALTIME - waited < 0.2 )); then
      opid="" stop_by=0
      if (( want )); then
        up=0
        if (( said_bye )); then
          start_at=0
        else
          now=$EPOCHSECONDS
          (( now - began >= 60 )) && fails=0
          start_at=$(( now + waits[fails < 5 ? fails + 1 : 5] ))
          print -u2 -- "garland: the overlay stopped; starting it again in $(( start_at - now )) s"
          (( fails++ ))
        fi
      fi
    elif (( EPOCHREALTIME - waited > 2 )); then
      heard=$EPOCHREALTIME
    elif (( EPOCHREALTIME - heard > 5 )); then
      print -u2 -- "garland: the overlay went quiet; ending it"
      stop_overlay KILL
      up=0 start_at=$(( EPOCHSECONDS + 5 ))
    fi
  elif (( post_fd )); then
    zselect -t 25 -r $post_fd
  else
    zselect -t 25
  fi

  (( post_fd )) && post_check
  if (( post_fd || EPOCHSECONDS < retry_at )); then :
  elif (( want && up || EPOCHREALTIME < peek_until )); then
    if (( EPOCHREALTIME >= next_frame )); then
      (( frame++ ))
      face $list[idx] $frame 1
      post $REPLY $step lit
      next_frame=$(( EPOCHREALTIME + (seen ? step : 5) ))
    fi
  elif [[ $shown != "dim $list[idx]" ]]; then
    face $list[idx] 0 0
    post $REPLY 1.5 "dim $list[idx]"
  fi
done
