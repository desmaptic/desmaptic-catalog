# Ruler, the live loop. The startup script is common.zsh and then this file (item.json).
#
# The button's own face (icon, colour, name) is the ruler at rest. While a measurement goes (the anchor file), the
# button shows the distance to the pointer whenever it is on the phone's screen:
# a crosshair, orange, "128×64" (across × up and down, whole points — the form the second tap copies; "↔ 128 ↕ 64"
# does not fit one line of an 80 pt button once both numbers have four digits, and a label that jumps between one
# line and two while the pointer moves is hard to read). After the second tap the copied size stays, with a
# check mark in green, for result_life seconds; then the button gets its own face back.
#
# The pointer reader is one osascript (JXA) coprocess, running while a measurement goes, whether the button is on
# the phone's screen or not: it also draws the measured area on the Mac's screen — a dot at the first spot and a
# frame from there to the pointer, in a see-through window on every display that clicks pass through and that
# never takes the focus. It looks at the pointer 30 times a second and moves the frame when the pointer moved;
# it prints a line when the size changes, at most ten a second (and every 2 s anyway — when this script is gone,
# that write ends it, and the frame with it; a reader silent for 5 s is stuck and is started again).
# A frame goes out only when what the button shows changes. That can be ten posts a second while the pointer
# moves, so they all go over ONE kept-alive connection to the agent, opened by zsh itself (zsh/net/tcp) — no
# process and no new connection per post, which would hold a port each for 30 s — and closed after 15 s unused.
# The token goes into the request from the environment through a builtin, never on a command line.
# Off screen: the reader still draws on the Mac, but nothing goes to the phone except a look every 2 s whether
# the button is back; at rest nothing but a look at the two files four times a second (no process is started).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/zselect zsh/net/tcp || { print -u2 -- "ruler: zsh modules zselect/net/tcp are missing"; exit 1 }
ruler_setup || exit 1

rpid="" ranchor=""      # the pointer reader and the start point it measures from
heard=0 odd=0           # when the reader last printed a line; whether it printed something else (reported once)
fd=0 used=0             # the connection to the agent, and when a request last went out on it

stop_reader() { [[ -n $rpid ]] && kill $rpid 2>/dev/null; rpid="" ranchor="" }
hang_up() { (( fd )) && ztcp -c $fd 2>/dev/null; fd=0 }
trap 'stop_reader; hang_up; exit 0' TERM INT HUP
trap 'stop_reader' EXIT
trap ':' PIPE           # a write to a connection the agent dropped fails and is sent again; the script lives on

# start_reader "<x> <y>": the reader, printing "<across> <up and down>". The connection is closed first: a child
# inherits it (ztcp does not close it on exec), and the reader would keep it open after this script hangs up.
start_reader() {
  hang_up
  coproc osascript -l JavaScript -e "$ruler_js"'
ObjC.import("QuartzCore");
ObjC.import("CoreGraphics");

// The measured area on the Mac: one see-through window per display, over everything (full screen apps too, on
// every Space), clicks pass through, never focused, no Dock icon. Returns draw(x, y): the frame from the start
// point to (x, y), global coordinates, like NSEvent.mouseLocation. Plain layers with a border and no paths: a
// JXA CGPath is lost (NSBezierPath.CGPath comes through empty, CGPathCreate… is never freed and CFRelease from
// JXA crashes), and the colours are CoreGraphics ones kept for the whole process — the CGColor of a temporary
// NSColor is freed with it, and the layer then draws from a dangling pointer (a crash on commit).
// There is no run loop: every change is committed and flushed to the screen at once.
function overlay(ax, ay) {
  $.NSApplication.sharedApplication.setActivationPolicy(1);                 // accessory
  const shade = $.CGColorCreateSRGB(0, 0, 0, 0.45), orange = $.CGColorCreateSRGB(1, 0.624, 0.039, 1);
  const screens = $.NSScreen.screens, parts = [];
  for (let i = 0; i < Number(screens.count); i++) {
    const f = screens.objectAtIndex(i).frame;
    const w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(f, 0, 2, false);   // borderless, buffered
    w.setOpaque(false);
    w.setBackgroundColor($.NSColor.clearColor);
    w.setHasShadow(false);
    w.setIgnoresMouseEvents(true);
    w.setReleasedWhenClosed(false);
    w.setLevel(1000);                                                        // the screen saver level
    w.setCollectionBehavior(1 | 16 | 64 | 256);    // all Spaces, stationary, out of the window cycle, full screen
    const under = $.CALayer.layer, line = $.CALayer.layer, dot = $.CALayer.layer;
    under.setBorderColor(shade); under.setBorderWidth(3.5);                  // a dark edge: seen on light and dark
    line.setBorderColor(orange); line.setBorderWidth(1.5);                   // the colour of the button while measuring
    dot.setBackgroundColor(orange); dot.setBorderColor(shade); dot.setBorderWidth(1); dot.setCornerRadius(4.5);
    const view = w.contentView;
    view.setWantsLayer(true);
    view.layer.addSublayer(under); view.layer.addSublayer(line); view.layer.addSublayer(dot);
    w.orderFrontRegardless;
    parts.push({ window: w, ox: f.origin.x, oy: f.origin.y, under: under, line: line, dot: dot });
  }
  return function (px, py) {
    const x = Math.min(ax, px), y = Math.min(ay, py), w = Math.abs(px - ax), h = Math.abs(py - ay);
    $.CATransaction.begin;
    $.CATransaction.setDisableActions(true);
    for (const s of parts) {
      s.under.setFrame($.CGRectMake(x - s.ox - 1.75, y - s.oy - 1.75, w + 3.5, h + 3.5));
      s.line.setFrame($.CGRectMake(x - s.ox - 0.75, y - s.oy - 0.75, w + 1.5, h + 1.5));
      s.dot.setFrame($.CGRectMake(ax - s.ox - 4.5, ay - s.oy - 4.5, 9, 9));
    }
    $.CATransaction.commit;
    $.CATransaction.flush;
  };
}

function run(argv) {
  const [ax, ay] = start(argv);
  const out = $.NSFileHandle.fileHandleWithStandardOutput;
  let draw = null;
  try { draw = overlay(ax, ay); }
  catch (e) {                          // the size still reaches the button
    const err = $.NSFileHandle.fileHandleWithStandardError;
    err.writeData($("ruler: cannot draw the frame on the screen: " + e + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
  }
  let last = "", said = 0, at = "";
  for (;;) {
    const p = $.NSEvent.mouseLocation, now = Date.now(), spot = p.x + " " + p.y;
    if (draw && spot !== at) {
      at = spot;
      draw(p.x, p.y);
    }
    const s = size(p, ax, ay);
    if ((s !== last && now - said >= 100) || now - said >= 2000) {
      out.writeData($(s + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
      last = s;
      said = now;
    }
    delay(1 / 30);
  }
}' -- ${=1}
  rpid=$! ranchor=$1 heard=$EPOCHREALTIME odd=0
}

# call <GET|POST> <route> [json]: one request on the open connection; one is opened when there is none, and the
# request goes once more on a new one when the agent had closed the old. code = the status (0: no answer),
# body = the answer's body.
call() {
  local method=$1 route=$2 json=$3 request line len=0 keep=1 try
  code=0 body=""
  for try in 1 2; do
    if (( ! fd )); then
      ztcp 127.0.0.1 9848 2>/dev/null || return 1
      fd=$REPLY
    fi
    used=$EPOCHSECONDS
    request="$method $route HTTP/1.1"$'\r\n'"Host: 127.0.0.1:9848"$'\r\n'"Authorization: Bearer ${DESMAPTIC_TOKEN}"$'\r\n'
    [[ $method == POST ]] && request+="Content-Type: application/json"$'\r\n'"Content-Length: ${#json}"$'\r\n'
    request+=$'\r\n'$json
    print -rn -u $fd -- "$request" 2>/dev/null && { IFS= read -r -t 3 -u $fd line } 2>/dev/null && break
    hang_up
    (( try == 2 )) && return 1
  done
  line=${line%$'\r'}
  [[ $line == HTTP/1.[01]' '<->(|' '*) ]] || { hang_up; return 1 }
  code=${${line#* }%% *}
  while :; do                                   # the headers, up to the empty line
    { IFS= read -r -t 3 -u $fd line } 2>/dev/null || { hang_up; code=0; return 1 }
    line=${line%$'\r'}
    [[ -z $line ]] && break
    case ${(L)line} in
      (content-length:*) len=${${line#*:}//[[:space:]]/} ;;
      (connection:*close*) keep=0 ;;
    esac
  done
  [[ $len == <-> ]] && (( ${#len} <= 6 && len <= 65536 )) || { hang_up; code=0; return 1 }
  if (( len )); then
    { IFS= read -r -t 3 -k $len -u $fd body } 2>/dev/null || { hang_up; code=0 body=""; return 1 }
  fi
  (( keep )) || hang_up                         # a refusal closes the connection on the agent's side too
  return 0
}

# on_screen: 0 when the phone shows the button, or cannot tell (an older app, no answer) — never rest on a guess.
on_screen() {
  call GET /api/view || return 0
  [[ $code == 200 ]] || return 0
  local answer=${(L)body//[[:space:]]/}
  [[ $answer == *'"view":null'* || $answer == *${(L)cell}* ]]
}

# post <rest | m <across> <down> | r <across> <down>>: shows it on the button; 0 when the agent took it.
# Measuring and the copied size set the icon and the colour with every title: a face cleared from outside
# comes back whole with the next change.
post() {
  local -a s=( ${=1} )
  local json
  case $s[1] in
    (m) json="{\"cellId\":\"$cell\",\"title\":\"$s[2]"'\u00d7'"$s[3]\",\"icon\":\"scope\",\"color\":\"#FF9F0A\"}" ;;
    (r) json="{\"cellId\":\"$cell\",\"title\":\"$s[2]"'\u00d7'"$s[3]\",\"icon\":\"checkmark\",\"color\":\"#30D158\"}" ;;
    (*) json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
  esac
  call POST /api/update-button $json && [[ $code == 200 ]]
}

shown=""                # what the phone shows: rest, "m <across> <down>", "r <across> <down>"; "" not known yet
want=rest               # what it should show
seen=-1                 # the button on screen: 1 yes, 0 no, -1 not known
look_at=0               # while off screen: when to ask the phone again
retry_at=0              # after a failed or dropped post: when to post again
reader_at=0             # after the reader quit by itself: when to start it again
failing=0               # a failed post was reported; quiet until one succeeds
while true; do
  now=$EPOCHSECONDS
  if read_anchor; then
    anchor=$REPLY
    [[ -n $rpid && $ranchor != "$anchor" ]] && stop_reader    # a new first tap: measure from the new spot
    # The frame on the Mac shows at once, before the phone is asked anything.
    [[ -z $rpid ]] && (( now >= reader_at )) && start_reader $anchor
    if (( seen != 1 && now >= look_at )); then
      if on_screen; then seen=1; else seen=0 look_at=$(( now + 2 )); fi
    fi
    if [[ -n $rpid ]]; then
      began=$EPOCHREALTIME
      if { IFS= read -r -t 0.25 -p line } 2>/dev/null; then
        heard=$EPOCHREALTIME
        # Behind after a slow answer from the agent: only the newest size counts.
        while { IFS= read -r -t 0 -p next } 2>/dev/null; do line=$next; done
        if [[ $line == <->' '<-> ]]; then
          want="m $line"
        elif (( ! odd )); then
          odd=1
          print -u2 -- "ruler: the pointer reader printed something that is not a size"
        fi
      elif (( EPOCHREALTIME - began < 0.2 )); then   # no wait, no line: the reader is gone
        print -u2 -- "ruler: the pointer reader stopped; starting it again in 5 s"
        stop_reader
        reader_at=$(( now + 5 ))
        zselect -t 25
      elif (( EPOCHREALTIME - heard > 5 )); then     # it prints at least every 2 s: silent longer, it is stuck
        print -u2 -- "ruler: the pointer reader went quiet; starting it again"
        stop_reader
      fi
      # The pointer rests and nothing went out for 2 s: is the button still on screen? Off it, the reader goes
      # on drawing the frame on the Mac; only the sizes stop going to the phone.
      if (( seen == 1 )) && [[ -n $rpid && $want == "$shown" ]] && (( EPOCHSECONDS - used >= 2 )) && ! on_screen; then
        seen=0 look_at=$(( now + 2 ))
      fi
    else
      zselect -t 25
    fi
  else
    stop_reader
    if read_result; then want="r $REPLY"; else want=rest; fi
    zselect -t 25
  fi

  # A size goes to the phone only while the button is on its screen (or it cannot tell): off it, up to ten posts
  # a second would be spent on a button nobody sees. The rest face and the copied size go either way.
  if [[ $want != "$shown" ]] && (( EPOCHSECONDS >= retry_at )) && ! [[ $seen == 0 && $want == "m "* ]]; then
    if post $want; then
      shown=$want failing=0
      answer=${body//[[:space:]]/}
      if [[ $answer == *'"visible":false'* ]]; then       # posted all the same: the phone keeps it for later
        seen=0 look_at=$(( EPOCHSECONDS + 2 ))
      else
        seen=1
      fi
      # The phone is not reading: the newest state reaches it once it does; meanwhile one post in 2 s.
      [[ $answer == *'"dropped":true'* ]] && retry_at=$(( EPOCHSECONDS + 2 ))
    else
      if (( ! failing )); then
        if (( code )); then print -u2 -- "ruler: update-button answered $code${body:+: ${body[1,200]}}"
        else print -u2 -- "ruler: no answer from the agent at 127.0.0.1:9848"; fi
      fi
      failing=1 retry_at=$(( EPOCHSECONDS + 2 ))
    fi
  fi
  (( fd && EPOCHSECONDS - used >= 15 )) && hang_up
done
