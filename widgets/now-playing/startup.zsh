#!/bin/zsh
# Now Playing: the track playing in Music or Spotify over a live spectrum of the sound the Mac plays (2×2 SVG face).
#
# The levels come from the agent (GET /api/audio/levels). The agent listens to the Mac's output only while a
# widget asks for levels, and this widget asks only while its button is on screen: the macOS "system audio
# recording" prompt appears the first time the page with this button is open, never before and never for
# anyone who does not use the widget. The track comes from the players themselves, through one persistent
# osascript helper that asks only apps that already run and never launches one. The macOS Automation
# question comes up the same way: only for a player that plays while this button is on screen.
#
# Every frame has the same 49 elements in the same order: the phone glides between frames instead of
# cross-fading. `zsh startup.zsh --face` prints the resting face (rest.svg of the catalog entry).
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/net/tcp zsh/system zsh/zselect || exit 1
trap 'exit 0' TERM INT HUP
trap '' PIPE
typeset -F SECONDS

port=9848
cell="{{CELL_ID}}"
token=$DESMAPTIC_TOKEN
frame_interval=0.0833        # 12 frames per second while the button is on screen
glide=0.092                  # 1.1 frame intervals, linear: the next frame takes over at constant speed
beat_glide=0.03              # a kick lands on the frame it arrives with

# MARK: - Face

# Bars and their reflection, one ready string per band and level (0…40), so a frame costs no arithmetic.
typeset -a BAR MIR FLAT
integer band level
for (( band = 0; band < 20; band++ )); do
  for (( level = 0; level <= 40; level++ )); do
    h=$(( level * 1.9 )); (( h < 2 )) && h=2
    m=$(( h * 0.22 )); (( m < 1 )) && m=1
    printf -v "BAR[band * 41 + level + 1]" "<rect id='b%d' x='%.1f' y='%.1f' width='6.0' height='%.1f' rx='2' fill='url(#spec)'/>" \
      $band "11.5 + $band * 9" "136 - $h" $h
    printf -v "MIR[band * 41 + level + 1]" "<rect id='m%d' x='%.1f' y='139.0' width='6.0' height='%.1f' rx='2' fill='url(#spec)' opacity='0.25'/>" \
      $band "11.5 + $band * 9" $m
  done
  FLAT+=(0)
done

# Attributes in single quotes: the frame goes into JSON with no escaping (the helper escapes track text).
TPL="<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 200'><defs>\
<linearGradient id='spec' gradientUnits='userSpaceOnUse' x1='10' y1='0' x2='190' y2='0'>\
<stop offset='0' stop-color='#FF375F'/><stop offset='0.35' stop-color='#BF5AF2'/>\
<stop offset='0.7' stop-color='#5E5CE6'/><stop offset='1' stop-color='#64D2FF'/></linearGradient>\
<radialGradient id='bloom' gradientUnits='userSpaceOnUse' cx='55' cy='136.0' r='%.1f'>\
<stop offset='0' stop-color='#FF375F' stop-opacity='%.2f'/><stop offset='0.55' stop-color='#BF5AF2' stop-opacity='%.2f'/>\
<stop offset='1' stop-color='#BF5AF2' stop-opacity='0'/></radialGradient>\
<clipPath id='lines'><rect x='10.0' y='0' width='180.0' height='56'/></clipPath></defs>\
<rect id='glow' x='0' y='0' width='200' height='200' fill='url(#bloom)'/>\
<text id='t0' x='%.1f' y='27' font-size='19' font-weight='600' fill='#FFFFFF' opacity='%.2f' clip-path='url(#lines)'>%s</text>\
<text id='t1' x='%.1f' y='27' font-size='19' font-weight='600' fill='#FFFFFF' opacity='%.2f' clip-path='url(#lines)'>%s</text>\
<text id='a0' x='%.1f' y='48' font-size='16' fill='#FFFFFF' opacity='%.2f' clip-path='url(#lines)'>%s</text>\
<text id='a1' x='%.1f' y='48' font-size='16' fill='#FFFFFF' opacity='%.2f' clip-path='url(#lines)'>%s</text>\
%s%s\
<rect id='track' x='10' y='161' width='180' height='4' rx='2' fill='#FFFFFF' opacity='%.2f'/>\
<rect id='done' x='10' y='161' width='%.1f' height='4' rx='2' fill='#FFFFFF' opacity='%.2f'/>\
<text id='elapsed' x='10' y='186' font-size='16' fill='#FFFFFF' opacity='0.6'>%s</text>\
<text id='remaining' x='190' y='186' font-size='16' text-anchor='end' fill='#FFFFFF' opacity='0.6'>%s</text></svg>"

# Marquee: a line wider than the box (x 10…190) scrolls instead of being cut. Widths are estimates in
# viewBox units, so they are read generously: a line scrolls from 150, and its two copies stand
# 1.2 widths + 40 apart. Long lines take turns: rest 2 s at the start, scroll one span at 30 units/s (the
# follower ends where the leader started, so nothing ever snaps back), then the next line. The copy that
# left the box is carried back while it is clipped away and invisible. A right-to-left line is mirrored.
typeset -a X O S W R
X=(10 210 10 210) O=(1 0 1 0) S=(0 0) W=(0 0) R=(0 0)
integer moving=0
place() {
  local -F t=$1 period=0 seg=0 within len start end since lead follow fo
  integer i j cycle passes
  local -a long
  X=(10 210 10 210) O=(1 0 1 0) S=(0 0) moving=0 long=()
  for i in 1 2; do (( W[i] > 150 )) && long+=($i); done
  (( $#long )) || return 0
  for i in $long; do (( period += 2 + (1.2 * W[i] + 40) / 30 )); done
  (( cycle = t / period, within = t - cycle * period ))
  for i in $long; do
    (( len = 1.2 * W[i] + 40, start = seg + 2, end = start + len / 30, seg = end ))
    (( passes = cycle + (within >= end), lead = 10, follow = 10 + len, fo = 1 ))
    if (( within >= start && within < end )); then
      (( lead -= (within - start) * 30, follow = lead + len, moving = 1 ))
    elif (( passes == 0 )); then
      (( fo = t < 4.0 / 3 ? 0 : 1 ))                 # new track: the follower may still show the old text
    else
      (( since = within >= end ? within - end : within + period - end ))
      if (( since < 2.0 / 3 )); then (( follow = 10 - len, fo = 0 ))   # just left: fade it out there
      elif (( since < 4.0 / 3 )); then fo=0; fi                      # carried to the other side, unseen
    fi
    (( j = 2 * i - 1 ))
    if (( passes % 2 == 0 )); then X[j]=$lead X[j+1]=$follow O[j]=1 O[j+1]=$fo
    else X[j]=$follow X[j+1]=$lead O[j]=$fo O[j+1]=1; fi
    (( R[i] )) && (( X[j] = 200 - X[j] - W[i], X[j+1] = 200 - X[j+1] - W[i] ))
    S[i]=1
  done
}

# m:ss, or h:mm:ss from one hour.
clock() {
  integer s=$1
  (( s < 0 )) && s=0; (( s > 359999 )) && s=359999
  if (( s >= 3600 )); then printf -v REPLY '%d:%02d:%02d' $(( s / 3600 )) $(( s / 60 % 60 )) $(( s % 60 ))
  else printf -v REPLY '%d:%02d' $(( s / 60 )) $(( s % 60 )); fi
}

# MARK: - State

typeset -a L; L=($FLAT)
integer bass=0 pulse=0 beat=0 audible=0 levels_ok=1
tr_kind=none tr_pos=0 tr_dur=0 tr_title="" tr_artist=""; typeset -F tr_at=-100
mq_key="" ; typeset -F mq_t=0 mq_last=0

# Builds `svg` from the current state; advances the marquee by the time since the previous frame.
build() {
  local title="♪" artist="" el="" rem="" t1="" a1="" bars="" mirror=""
  local -F now=$SECONDS pos bo top=0.5 prog=-1 dt
  integer i k dim=1 r
  if [[ $tr_kind == (play|pause) ]] && (( now - tr_at < 5 )); then
    title=${tr_title:-♪} artist=$tr_artist
    [[ $tr_kind == play ]] && dim=0
    (( pos = tr_pos + (dim ? 0 : now - tr_at) ))
    if (( tr_dur > 1 )); then
      (( pos < 0 )) && pos=0; (( pos > tr_dur )) && pos=$tr_dur
      (( prog = pos / tr_dur ))
      clock $pos; el=$REPLY
      clock $(( tr_dur - pos )); rem="-$REPLY"
    fi
  elif [[ $tr_kind == lock ]] || (( cp_asking )); then
    title="🔒"                                         # denied, or the consent dialog is open on the Mac
  elif (( audible )); then
    title="♫" dim=0
  fi
  (( dim )) || top=1
  # A new line starts its marquee from rest. Glyphs never scroll; text keeps the widths the helper measured.
  if [[ "$title"$'\n'"$artist" != "$mq_key" ]]; then
    mq_key="$title"$'\n'"$artist" mq_t=0 W=(0 0) R=(0 0)
    if [[ -n $artist || $title == "$tr_title" ]] && [[ $tr_kind == (play|pause) ]]; then
      W=(${=tr_w}) R=(${=tr_r})
      [[ $title == "$tr_title" ]] || W[1]=0 R[1]=0
    fi
  fi
  (( dt = now - mq_last )); (( dt < 0 )) && dt=0; (( dt > 0.25 )) && dt=0.25; mq_last=$now
  (( ! dim || moving )) && (( mq_t += dt ))           # paused: a pass under way finishes, then it rests
  place $mq_t
  (( S[1] )) && t1=$title
  (( S[2] )) && a1=$artist
  for (( i = 1; i <= 20; i++ )); do
    (( L[i] > 40 )) && L[i]=40
    (( k = i * 41 - 40 + L[i] ))
    bars+=$BAR[k] mirror+=$MIR[k]
  done
  (( bo = 0.12 + 0.45 * bass / 40 + 0.35 * pulse / 40 )); (( bo > 0.9 )) && bo=0.9
  (( r = prog < 0 ? 0 : prog * 360 + 0.5 ))
  printf -v svg "$TPL" "55 + 95 * $bass / 40.0" $bo "$bo * 0.35" \
    $X[1] "$top * $O[1]" "$title" $X[2] "$top * $O[2]" "$t1" \
    $X[3] "0.6 * $top * $O[3]" "$artist" $X[4] "0.6 * $top * $O[4]" "$a1" \
    "$bars" "$mirror" $(( prog < 0 ? 0 : 0.18 )) "$r / 2.0" $(( prog < 0 ? 0 : 0.9 )) "$el" "$rem"
}

if [[ $1 == --face ]]; then
  build
  print -r -- "$svg"
  exit 0
fi

last_log=""
log_once() { [[ $1 == "$last_log" ]] && return; last_log=$1; print -u2 -r -- "now playing: $1"; }

# MARK: - Agent API: one keep-alive connection, HTTP/1.1 by hand

sock="" http_status=0 http_body=""
integer api_failures=0 auth_failures=0
typeset -F api_retry_at=0

api_close() { [[ -n $sock ]] && ztcp -c $sock 2>/dev/null; sock=""; }

api_connect() {
  (( SECONDS >= api_retry_at )) || return 1
  if ztcp 127.0.0.1 $port 2>/dev/null; then sock=$REPLY api_failures=0; return 0; fi
  (( api_failures++ ))
  (( api_retry_at = SECONDS + (api_failures > 5 ? 5 : 0.25 * (1 << (api_failures - 1))) ))
  log_once "the agent does not answer on port $port; retrying"
  # Nobody left to talk to: the agent that started this script is gone.
  (( api_failures % 12 == 0 )) && [[ $(ps -o ppid= -p $$ 2>/dev/null) == *[[:space:]]1 ]] && exit 0
  return 1
}

# api METHOD TARGET [BODY]: sets http_status and http_body; returns 1 when no answer came.
api() {
  local method=$1 target=$2 body=$3 request buf chunk header line
  integer try len close
  http_status=0 http_body=""
  for try in 1 2; do
    [[ -n $sock ]] || api_connect || return 1
    request="$method $target HTTP/1.1"$'\r\n'"Host: 127.0.0.1"$'\r\n'"Authorization: Bearer $token"$'\r\n'
    [[ -n $body ]] && request+="Content-Type: application/json"$'\r\n'"Content-Length: ${#body}"$'\r\n'
    if ! print -rn -u $sock -- "$request"$'\r\n'"$body" 2>/dev/null; then api_close; continue; fi
    buf=""
    while [[ $buf != *$'\r\n\r\n'* ]]; do
      sysread -i $sock -t 3 chunk
      case $? in
        0) buf+=$chunk ;;
        4) api_close; log_once "the agent did not answer $target in 3 s"; return 1 ;;
        *) api_close; buf=""; break ;;            # closed (an idle keep-alive connection): once more on a new one
      esac
    done
    [[ -n $buf ]] || continue
    header=${buf%%$'\r\n\r\n'*} http_body=${buf#*$'\r\n\r\n'} len=0 close=0
    for line in ${(f)header}; do
      line=${(L)line%$'\r'}
      case $line in
        content-length:*) len=${line#*:} ;;
        connection:*close*) close=1 ;;
      esac
    done
    while (( ${#http_body} < len )); do
      sysread -i $sock -t 3 chunk || { api_close; return 1; }
      http_body+=$chunk
    done
    line=${header%%$'\r'*}; http_status=${${line#* }%% *}
    [[ $http_status == <-> ]] || http_status=0
    (( close )) && api_close
    if (( http_status == 401 )); then
      # A stale token never heals by itself: the agent restarts the widget with a fresh one.
      (( ++auth_failures >= 3 )) && { print -u2 "now playing: the agent does not accept DESMAPTIC_TOKEN"; exit 4; }
    else
      auth_failures=0
    fi
    return 0
  done
  return 1
}

# MARK: - Visibility: nothing is sampled or drawn while the button is off screen

integer visible=0 shown=0 unknown_views=0
typeset -F seen_at=0 view_at=-100

# shown = the phone is connected and shows this button, or cannot say which buttons it shows. Right after
# connecting, the phone may not have said it yet: only a view unknown for 3 checks in a row counts as shown.
view_check() {
  view_at=$SECONDS
  api GET /api/view || return 1
  if (( http_status == 404 )); then shown=1                     # an agent too old to know: assume on screen
  elif (( http_status == 200 )); then
    shown=0
    if [[ $http_body == *'"connected":true'* ]]; then
      if [[ $http_body == *'"view":null'* ]]; then (( ++unknown_views >= 3 )) && shown=1
      else unknown_views=0; [[ ${(U)http_body} == *"\"${(U)cell}\""* ]] && shown=1; fi
    fi
  else
    return 1
  fi
  (( shown )) && seen_at=$SECONDS
  return 0
}

# MARK: - Players: one osascript helper, one question at a time, never waited for

read -r -d '' JXA <<'JS'
ObjC.import("Foundation");
ObjC.import("AppKit");
ObjC.import("stdlib");
ObjC.bindFunction("AEDeterminePermissionToAutomateTarget", ["int", ["void *", "unsigned int", "unsigned int", "bool"]]);

// A line on stdin is a question; the answer is one tab-separated line:
//   T  kind  position  duration  titleWidth  artistWidth  rtl  title  artist     kind: play | pause | none | lock
//   A  bundle id                                      the Automation consent dialog for that player is open
const players = [
  { id: "com.apple.Music", scale: 1, note: "com.apple.Music.playerInfo" },
  { id: "com.spotify.client", scale: 0.001, note: "com.spotify.client.PlaybackStateChanged" },
];
for (const p of players) Object.assign(p, { access: "ok", announced: false, asked: false, retryAt: 0, reported: 0, last: null });

const stdin = $.NSFileHandle.fileHandleWithStandardInput;
const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
function emit(line) { stdout.writeData($(line + "\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
function uptime() { return $.NSProcessInfo.processInfo.systemUptime; }
function fcc(s) { return ((s.charCodeAt(0) << 24) | (s.charCodeAt(1) << 16) | (s.charCodeAt(2) << 8) | s.charCodeAt(3)) >>> 0; }

const D = $.NSAppleEventDescriptor;
function prop(code, container) {
  const r = D.recordDescriptor;
  r.setDescriptorForKeyword(D.descriptorWithTypeCode(fcc("prop")), fcc("want"));
  r.setDescriptorForKeyword(container || D.nullDescriptor, fcc("from"));
  r.setDescriptorForKeyword(D.descriptorWithEnumCode(fcc("prop")), fcc("form"));
  r.setDescriptorForKeyword(D.descriptorWithTypeCode(fcc(code)), fcc("seld"));
  return r.coerceToDescriptorType(fcc("obj "));
}
const STATE = prop("pPlS"), POSITION = prop("pPos"), STREAM = prop("pStT"), CURRENT = prop("pTrk");
const NAME = prop("pnam", CURRENT), ARTIST = prop("pArt", CURRENT), DURATION = prop("pDur", CURRENT);

// A read-only "get" to one process: it cannot launch an app, never raises the consent dialog (-1744 instead)
// and gives up after 2 s.
function get(spec, pid) {
  const event = D.appleEventWithEventClassEventIDTargetDescriptorReturnIDTransactionID(
    fcc("core"), fcc("getd"), D.descriptorWithProcessIdentifier(pid), -1, 0);
  event.setParamDescriptorForKeyword(spec, fcc("----"));
  // The NSError comes back in $(): reading a Ref() after an error crashes osascript (EXC_BAD_ACCESS, macOS 26).
  const error = $();
  const reply = event.sendEventWithOptionsTimeoutError(0x3 | 0x10 | 0x20000, 2, error);
  if (reply.isNil()) throw { code: error.isNil() ? -1 : error.code };
  const status = reply.paramDescriptorForKeyword(fcc("errn"));
  if (!status.isNil() && status.int32Value != 0) throw { code: status.int32Value };
  const value = reply.paramDescriptorForKeyword(fcc("----"));
  return value.isNil() || value.descriptorType == fcc("null") ? null : value;
}
// null: the question failed (an empty answer is "")
function text(spec, pid) {
  try { const v = get(spec, pid); return v ? ObjC.unwrap(v.stringValue) || "" : ""; } catch (e) { return null; }
}
function seconds(spec, pid) {
  try { const v = get(spec, pid); const n = v ? v.doubleValue : 0; return isFinite(n) && n > 0 ? n : 0; } catch (e) { return 0; }
}

function pidOf(p) {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(p.id);
  for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i);
    if (app.finishedLaunching) return app.processIdentifier;
  }
  return 0;
}

// The consent dialog waits for the user as long as it takes; the widget keeps drawing meanwhile.
function askConsent(p, pid) {
  emit("A\t" + p.id);
  const status = $.AEDeterminePermissionToAutomateTarget(D.descriptorWithProcessIdentifier(pid).aeDesc, fcc("****"), fcc("****"), true);
  console.log("now playing: " + p.id + " automation consent answered " + status);
  p.retryAt = 0;
}

// A player that started before this helper did never announces it. What plays right now needs no permission
// to see: coreaudiod holds a sleep assertion "created for" every process that sends sound to an output
// (`Resources: audio-out …` in pmset). Read at most every 5 s, and only while a player waits for its question.
function soundOutputPids(assertions) {
  const pids = [];
  for (const block of assertions.split(/\n(?=\s*pid \d+\()/)) {
    const m = block.match(/Created for PID: (\d+)/);
    if (m && /Resources:.*\baudio-out\b/.test(block)) pids.push(+m[1]);
  }
  return pids;
}
let soundPids = [], soundReadAt = -100;
function playsSound(pid) {
  if (uptime() - soundReadAt >= 5) {
    soundReadAt = uptime();
    soundPids = [];
    try {
      const task = $.NSTask.alloc.init, pipe = $.NSPipe.pipe;
      task.setExecutableURL($.NSURL.fileURLWithPath("/usr/bin/pmset"));
      task.setArguments($(["-g", "assertions"]));
      task.setStandardInput($.NSFileHandle.fileHandleWithNullDevice);   // stdin is the widget's question pipe
      task.setStandardError($.NSFileHandle.fileHandleWithNullDevice);
      task.setStandardOutput(pipe);
      if (task.launchAndReturnError($())) {
        soundPids = soundOutputPids(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(
          pipe.fileHandleForReading.readDataToEndOfFile, $.NSUTF8StringEncoding)) || "");
      }
    } catch (e) { console.log("now playing: pmset " + e); }
  }
  return soundPids.includes(pid);
}

function failed(p, pid, code) {
  if (code == -1744) {                  // never asked: ask once, and only for a player that plays —
    p.access = "consent";               // a Spotify idling in the background must not pop a dialog
    p.retryAt = uptime() + 2;
    p.last = null;
    if (!p.asked && !p.announced && playsSound(pid)) p.announced = true;
    if (!p.asked && p.announced) { p.asked = true; askConsent(p, pid); }
  } else if (code == -1743) {           // "Don't Allow": Privacy & Security → Automation
    p.access = "denied";
    p.retryAt = uptime() + 5;
    p.last = null;
  } else if (code == -600 || code == -609) {
    p.last = null;                      // quit between the check and the question
  } else if (code == -1712) {           // hung or busy: leave it alone for a while
    p.retryAt = uptime() + 10;
  }                                     // anything else is transient: the last good answer stays for 5 s
  if (code != p.reported) {
    p.reported = code;
    console.log("now playing: " + p.id + " Apple event error " + code
      + (code == -1743 ? " (allow the agent to control it in System Settings → Privacy & Security → Automation)" : ""));
  }
}

// C0/C1 controls and U+FFFE/U+FFFF are not XML, line breaks would draw over the next line, bidi overrides
// flip the rest of it; a lone surrogate cannot be written as UTF-8.
function clean(s) {
  let out = "";
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if ((c >= 0x09 && c <= 0x0D) || c == 0x85 || c == 0x2028 || c == 0x2029) out += " ";
    else if (c <= 0x1F || (c >= 0x7F && c <= 0x9F) || c == 0xFFFE || c == 0xFFFF || (c >= 0x202A && c <= 0x202E)
      || (c >= 0x2066 && c <= 0x2069) || (c >= 0xD800 && c <= 0xDFFF)) continue;
    else out += ch;
  }
  const words = out.split(/\s+/).filter(w => w.length > 0);
  const chars = Array.from(words.join(" "));
  return chars.length > 120 ? chars.slice(0, 119).join("") + "…" : chars.join("");   // a pass of at most ~1 min
}
// Escaped for XML text and for the JSON string the frame travels in.
function markup(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/\\/g, "\\\\");
}
// Hebrew, Arabic and neighbours: such a line starts at its right end.
function rtl(s) {
  const m = s.match(/\p{Alphabetic}/u);
  if (!m) return 0;
  const c = m[0].codePointAt(0);
  return (c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF) ? 1 : 0;
}
// Width in viewBox units with the phone's font (system, fixed-width figures); an em estimate as a fallback.
function font(size, weight) { try { return $.NSFont.monospacedDigitSystemFontOfSizeWeight(size, weight); } catch (e) { return null; } }
const titleFont = font(19, 0.3), artistFont = font(16, 0);
const widths = {};
function width(s, f, size) {
  if (!s) return 0;
  const key = size + ":" + s;
  if (widths[key] !== undefined) return widths[key];
  let w = 0;
  try { w = $.NSString.stringWithString(s).sizeWithAttributes($.NSDictionary.dictionaryWithObjectForKey(f, $.NSFontAttributeName)).width; }
  catch (e) { w = 0; }
  if (!(w > 0 && isFinite(w))) {
    w = 0;
    for (const ch of s) w += (ch.codePointAt(0) >= 0x1100 ? 1 : 0.62) * size;
  }
  if (Object.keys(widths).length > 64) for (const k in widths) delete widths[k];
  return widths[key] = w;
}

function emitTrack(t, position) {
  emit(["T", t.playing ? "play" : "pause", position.toFixed(1), t.duration.toFixed(1), t.titleWidth.toFixed(1),
        t.artistWidth.toFixed(1), t.rtl, markup(t.title), markup(t.artist)].join("\t"));
}

// Each player keeps its last good answer (`last`). A player that is backing off, or whose state question
// failed for a passing reason (busy for 2 s, a stray error), answers with it for up to 5 s, its position
// running on; a quit, a stop or a consent error clears it at once. Otherwise one slow Apple event would
// replace the track by ♫ for a second and restart the marquee.
function answer() {
  let pick = null;
  for (const p of players) {
    const pid = pidOf(p);
    if (!pid) { p.access = "ok"; p.last = null; continue; }
    let c = null;
    if (uptime() >= p.retryAt) {
      try {
        const v = get(STATE, pid), state = v ? v.enumCodeValue : 0;
        p.access = "ok"; p.reported = 0;
        c = { p, pid, playing: state == fcc("kPSP"), prev: p.last };
        p.last = null;                                                  // the fresh answer replaces it
        if (!state || state == fcc("kPSS")) continue;                   // stopped
      } catch (e) { failed(p, pid, e.code); }
    }
    if (!c && p.last && uptime() - p.last.at < 5) c = { p, playing: p.last.playing, kept: p.last };
    if (!c) continue;
    if (c.playing || !pick) pick = c;
    if (c.playing) break;                                               // a playing player wins, Music first
  }
  if (!pick) {
    const locked = players.some(p => p.access == "denied" || (p.access == "consent" && p.announced));
    return emit(["T", locked ? "lock" : "none", "0", "0", "0", "0", "00", "", ""].join("\t"));
  }
  const { p, pid, playing, prev, kept } = pick;
  if (kept) return emitTrack(kept, kept.position + (kept.playing ? uptime() - kept.readAt : 0));
  const name = text(NAME, pid), duration = seconds(DURATION, pid) * p.scale, position = seconds(POSITION, pid);
  // at: when the answer was last whole (it counts for 5 s from then); readAt: when the position was read.
  const now = uptime(), t = { playing, duration, position, at: now, readAt: now };
  if (name === null && prev && now - prev.at < 5) {
    // The name did not come this time: the same player's last one, for a moment, rather than ♪.
    Object.assign(t, { at: prev.at, title: prev.title, artist: prev.artist, titleWidth: prev.titleWidth,
                       artistWidth: prev.artistWidth, rtl: prev.rtl });
  } else {
    let title = clean(name ?? ""), artist = clean(text(ARTIST, pid) ?? "");
    if (p.id == "com.apple.Music") {
      const stream = clean(text(STREAM, pid) ?? "");
      if (stream) { artist = title; title = stream; }                   // radio: the song, the station below
    }
    Object.assign(t, { title, artist, titleWidth: width(title, titleFont, 19), artistWidth: width(artist, artistFont, 16),
                       rtl: "" + rtl(title) + rtl(artist) });
  }
  p.last = t;
  emitTrack(t, t.position);
}

// Music and Spotify tell everyone when they start playing (no permission needed): from then on asking
// for consent makes sense.
ObjC.registerSubclass({
  name: "DesmapticNowPlayingHelper",
  methods: {
    "player:": { types: ["void", ["id"]], implementation: function (note) {
      const info = note.userInfo;
      if (info.isNil() || ObjC.unwrap(info.objectForKey("Player State")) != "Playing") return;
      const name = ObjC.unwrap(note.name);
      for (const p of players) if (p.note == name) p.announced = true;
    } },
    "input:": { types: ["void", ["id"]], implementation: function (note) {
      if (stdin.availableData.length == 0) $.exit(0);                  // the widget is gone
      try { answer(); } catch (e) { console.log("now playing: " + e); emit("T\tnone\t0\t0\t0\t0\t00\t\t"); }
      stdin.waitForDataInBackgroundAndNotify;
    } },
  },
});
const helper = $.DesmapticNowPlayingHelper.alloc.init;
for (const p of players) $.NSDistributedNotificationCenter.defaultCenter.addObserverSelectorNameObject(helper, "player:", p.note, $());
$.NSNotificationCenter.defaultCenter.addObserverSelectorNameObject(helper, "input:", $.NSFileHandleDataAvailableNotification, stdin);
stdin.waitForDataInBackgroundAndNotify;
while (true) {
  if (!$.NSRunLoop.currentRunLoop.runModeBeforeDate($.NSDefaultRunLoopMode, $.NSDate.dateWithTimeIntervalSinceNow(60))) delay(1);
}
JS

cp_in="" cp_out=""
integer cp_pid=0 cp_fails=0 cp_busy=0 cp_asking=0
typeset -F cp_asked_at=-100 cp_started_at=0 cp_retry_at=0
tr_w="0 0" tr_r="0 0"

cp_start() {
  (( SECONDS >= cp_retry_at )) || return 1
  # The helper must not keep a copy of the agent connection: closing it here would not close it then.
  if [[ -n $sock ]]; then coproc /usr/bin/osascript -l JavaScript -e "$JXA" {sock}>&-
  else coproc /usr/bin/osascript -l JavaScript -e "$JXA"; fi
  cp_pid=$!
  exec {cp_out}<&p {cp_in}>&p
  cp_started_at=$SECONDS cp_busy=0 cp_asking=0
}

cp_stop() {
  [[ -n $cp_in ]] && exec {cp_in}>&-
  [[ -n $cp_out ]] && exec {cp_out}<&-
  cp_in="" cp_out=""
  (( cp_pid )) && kill $cp_pid 2>/dev/null
  cp_pid=0 cp_busy=0 cp_asking=0
  (( cp_fails = SECONDS - cp_started_at < 30 ? cp_fails + 1 : 1 ))
  (( cp_retry_at = SECONDS + (cp_fails > 4 ? 30 : 1 << cp_fails) ))
}

# Takes every answer that is already there; never waits for one.
cp_drain() {
  local line
  local -a f
  while [[ -n $cp_out ]] && zselect -t 0 -r $cp_out; do
    if ! IFS= read -r -t 1 -u $cp_out line; then log_once "the player helper stopped; restarting it"; cp_stop; return; fi
    f=("${(@ps:\t:)line}")
    if [[ $f[1] == T && $#f == 9 && $f[2] == (play|pause|none|lock) && "$f[3]$f[4]$f[5]$f[6]" != *[^0-9.]* ]]; then
      tr_kind=$f[2] tr_pos=$f[3] tr_dur=$f[4] tr_w="$f[5] $f[6]" tr_r="${f[7][1]} ${f[7][2]}" tr_title=$f[8] tr_artist=$f[9]
      tr_at=$SECONDS cp_busy=0 cp_asking=0
    elif [[ $f[1] == A ]]; then
      cp_asking=1
    fi
  done
}

# Once a second while on screen: one question, the answer is picked up by a later frame.
cp_service() {
  cp_drain
  [[ -n $cp_in ]] || cp_start || return
  if (( cp_busy )); then
    # A consent dialog may stay open for as long as the user likes; anything else answers within seconds.
    (( ! cp_asking && SECONDS - cp_asked_at > 10 )) && { log_once "the player helper hangs; restarting it"; cp_stop; }
    return
  fi
  (( SECONDS - cp_asked_at >= 1 )) || return
  if print -r -u $cp_in q 2>/dev/null; then cp_busy=1 cp_asked_at=$SECONDS; else cp_stop; fi
}

# MARK: - Frames

sent="" rejected=""
typeset -F sent_at=-100 post_retry_at=0

poll_levels() {
  local -a f
  L=($FLAT) bass=0 pulse=0 beat=0 audible=0
  (( levels_ok )) || return
  api GET "/api/audio/levels?client=$cell" || return
  if (( http_status == 404 )); then
    levels_ok=0
    log_once "this agent has no /api/audio/levels: the bars stay flat"
    return
  fi
  (( http_status == 200 )) || return
  f=(${=http_body})
  # starting / error / unsupported: flat bars (the agent keeps retrying by itself)
  [[ $#f == 25 && $f[1] == ok && "${(j::)f[2,25]}" == <-> ]] || return
  audible=$f[2] bass=$f[3] pulse=$f[4] beat=$f[5] L=($f[6,25])
  (( bass > 40 )) && bass=40; (( pulse > 40 )) && pulse=40
}

go_visible() {
  visible=1 sent="" seen_at=$SECONDS mq_last=$SECONDS
  # Ask the players first, so the first frame does not show a stale track or a blank one.
  cp_asked_at=-100
  cp_service
  (( cp_busy )) && [[ -n $cp_out ]] && zselect -t 30 -r $cp_out
  cp_drain
}

post_frame() {
  api POST /api/update-button "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$svg\",\"duration\":$1,\"easing\":\"linear\",\"fit\":\"contain\"}}" || return
  case $http_status in
    200)
      sent=$svg sent_at=$SECONDS seen_at=$SECONDS last_log=""
      [[ $http_body == *'"visible":false'* ]] && visible=0 ;;
    400)
      rejected=$svg                                   # a 400 is about this exact frame: never send it again
      log_once "update-button 400: $http_body" ;;
    *)
      post_retry_at=$(( SECONDS + 1 ))
      log_once "update-button $http_status" ;;
  esac
}

tick() {
  if (( ! visible )); then
    # Off screen: no levels (the agent stops listening once no widget asks), no player questions.
    (( SECONDS - view_at >= 1 )) && view_check && (( shown )) && go_visible
    return
  fi
  cp_service
  poll_levels
  build
  if [[ "$svg" != "$rejected" ]] && (( SECONDS >= post_retry_at )) && { [[ "$svg" != "$sent" ]] || (( SECONDS - sent_at > 30 )) }; then
    # A kick lands at once, unless a line is scrolling: a short glide would jerk it.
    if (( beat && ! moving )); then post_frame $beat_glide; else post_frame $glide; fi
  fi
  # Nothing to send for a while (silence, a paused track): still notice when the page is left.
  if (( visible && SECONDS - seen_at > 2 && SECONDS - view_at >= 2 )); then
    view_check && (( ! shown )) && visible=0
  fi
}

# Until the phone says otherwise, the button counts as off screen: not even one levels request before that.
view_check && (( shown )) && go_visible
typeset -F next=$SECONDS wait
integer cs
while true; do
  tick
  if (( visible )); then (( next += frame_interval )); else (( next = SECONDS + 1 )); fi
  (( wait = next - SECONDS ))
  (( wait < -0.25 )) && { next=$SECONDS; wait=0; }    # fell behind (the Mac slept): no burst of frames
  (( cs = wait * 100 + 0.5 ))
  (( cs > 0 )) && zselect -t $cs
done
