#!/bin/zsh
# Reminders › Today: how many reminders are due today or earlier and still open, how many of them are overdue, and the
# first three of them with their time (2×2 SVG face). The tap opens Reminders on its Today list (tap.zsh).
#
# Nothing is read while the phone does not show the button: the reader below runs only then. It asks macOS for access
# to Reminders the first time it runs — so the question whether the agent may have full access to your reminders comes
# up when the user first sees the widget, never at install. Every frame has the same 23 elements in the same order: the
# phone glides between them.
# `zsh startup.zsh --face <state> <total> <overdue> [<row>]…` prints one frame (rest.svg and demo.svg are made that way).
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "reminders: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv

reader=0
trap '(( reader > 0 )) && kill $reader 2>/dev/null; exit 0' TERM INT HUP

# One frame of the face.
#   $1 state: rest (nothing read yet) | ask (waiting for the answer to the access question) | denied (no access)
#             calm (nothing due) | list
#   $2 open reminders due today or earlier   $3 how many of them are overdue
#   $4 $5 $6 the first three: "<o (overdue) | t (today)>|<time or date>|<list colour #RRGGBB>|<title>"
reminders_frame() {
  emulate -L zsh
  export LC_ALL=C
  RF_ST=${1:-rest} RF_N=${2:-0} RF_L=${3:-0} RF_1=${4:-} RF_2=${5:-} RF_3=${6:-} awk '
    function colour(c, fallback) { return (c ~ /^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) ? toupper(c) : fallback }
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }

    # Text is measured in em of the semibold system font, one UTF-8 character at a time (the locale is C,
    # so awk sees bytes): Latin by letter shape, other alphabets 0.6, CJK 0.96, emoji 1.25.
    function em(c, b, n) {
      if (n == 4) return 1.25
      if (n == 3) return (b == 226) ? 0.7 : 0.96
      if (n == 2) return 0.6
      if (c ~ /[0-9]/) return 0.62
      if (c == " ") return 0.25
      if (c ~ /[ijl.,:;!|\047]/) return 0.28
      if (c ~ /[frtI()\/"-]/) return 0.38
      if (c ~ /[mwMW@%]/) return 0.86
      if (c ~ /[A-Z&#?]/) return 0.68
      return 0.56
    }
    function chars(s,   i, b, n, k) {      # s → CH[1..k], CW[1..k] (em)
      k = 0; i = 1
      while (i <= length(s)) {
        b = ord[substr(s, i, 1)]
        n = (b >= 240) ? 4 : (b >= 224) ? 3 : (b >= 192) ? 2 : 1
        k++; CH[k] = substr(s, i, n); CW[k] = em(CH[k], b, n); i += n
      }
      return k
    }
    function join(a, b,   i, r) { r = ""; for (i = a; i <= b; i++) r = r CH[i]; return r }
    function fit(s, size, room,   n, i, w, r) {   # s on one line; cut with … when it does not fit
      n = chars(s)
      w = 0; for (i = 1; i <= n; i++) w += CW[i] * size
      if (w <= room) return s
      w = 0.9 * size
      for (i = 1; i <= n; i++) { if (w + CW[i] * size > room) break; w += CW[i] * size }
      r = join(1, i - 1); sub(/ +$/, "", r)
      return r "\342\200\246"
    }
    function textw(s, size,   n, i, w) { n = chars(s); w = 0; for (i = 1; i <= n; i++) w += CW[i] * size; return w }
    function show(s) { return (s == "") ? "\342\200\224" : esc(s) }   # never an empty <text>
    function f2(x) { return sprintf("%.2f", x) }
    function row(s, i,   p) {                     # "k|label|colour|title" → RK[i] RL[i] RC[i] RT[i]
      RK[i] = ""; RL[i] = ""; RC[i] = ""; RT[i] = ""
      p = index(s, "|"); if (!p) return 0; RK[i] = substr(s, 1, p - 1); s = substr(s, p + 1)
      p = index(s, "|"); if (!p) return 0; RL[i] = substr(s, 1, p - 1); s = substr(s, p + 1)
      p = index(s, "|"); if (!p) return 0; RC[i] = substr(s, 1, p - 1); RT[i] = substr(s, p + 1)
      if (RK[i] != "o" && RK[i] != "t") return 0
      if (length(RL[i]) > 16) RL[i] = ""
      return 1
    }

    BEGIN {
      for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
      st = ENVIRON["RF_ST"]
      if (st !~ /^(rest|ask|denied|calm|list)$/) st = "rest"
      n = int(ENVIRON["RF_N"] + 0); late = int(ENVIRON["RF_L"] + 0)
      if (n < 0) n = 0; if (late < 0) late = 0; if (late > n) late = n
      if (st == "list" && n == 0) st = "calm"
      live = (st == "list"); hot = live && late > 0
      liveO = live ? 1 : 0

      # the header: the number due, then a pink clock with the number overdue
      ns = (n > 999) ? "999+" : n ""
      ls = (late > 999) ? "999+" : late ""
      px = 18 + textw(ns, 46) + 12
      pw = 31 + textw(ls, 24) + 13
      cx = px + 18
      pillO = hot ? 1 : 0

      # the rows: a ring in the list colour, the title, below it the time (today) or the date (an earlier day);
      # overdue times and dates are pink. A row without a time centres its title on the ring.
      for (i = 1; i <= 3; i++) {
        has[i] = live && row(ENVIRON["RF_" i], i)
        Y = 84 + (i - 1) * 40
        TY[i] = (has[i] && RL[i] == "") ? Y + 9.5 : Y
        WY[i] = Y + 19
        T[i] = has[i] ? fit(RT[i], 18, 144) : ""
        DC[i] = colour(RC[i], "#BF5AF2")
        WC[i] = (RK[i] == "o") ? "#FF5C80" : "#FFFFFF"
        WO[i] = !has[i] || RL[i] == "" ? 0 : (RK[i] == "o" ? 1 : 0.6)
        RO[i] = has[i] ? 1 : 0
      }

      # the checklist: hollow while nothing is read, ticked when nothing is due, grey and struck out without access;
      # it fades and shrinks as the list comes in
      s1 = "#BF5AF2"; s2 = "#64D2FF"; iA = 1; boxF = 0; tickO = 0; lineO = 0.9; slashO = 0; sx2 = -52; sy2 = 52
      if (st == "calm")   { boxF = 1; tickO = 1; lineO = 0.35 }
      if (st == "denied") { s1 = "#FFFFFF"; s2 = "#FFFFFF"; iA = 0.35; slashO = 1; sx2 = 52; sy2 = -52 }
      iO = live ? 0 : 1
      is = live ? 0.7 : 1.1

      # the glow behind: purple at rest, indigo when all is done, pink when something is overdue
      bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 84; bY = 104
      if (st == "calm")   { bC = "#5E5CE6"; bA = 0.18; mC = "#64D2FF"; bM = 0.05; bR = 90 }
      if (st == "denied") { bC = "#FF375F"; bA = 0.10; mC = "#BF5AF2"; bM = 0.03; bR = 80 }
      if (live)           { bC = "#5E5CE6"; bA = 0.20; mC = "#BF5AF2"; bM = 0.06; bR = 120; bY = 36 }
      if (hot)            { bC = "#FF375F"; bA = 0.30; mC = "#BF5AF2"; bM = 0.08 }
      cardY = live ? 0 : 12

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"inkG\" gradientUnits=\"userSpaceOnUse\" x1=\"-46\" y1=\"0\" x2=\"46\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"%s\"/></linearGradient>", s1, f2(iA), s2, f2(iA)
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", bC, f2(bA), mC, f2(bM), mC
      printf "</defs>"
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"%d\" r=\"%d\" fill=\"url(#bloomG)\"/>", bY, bR

      printf "<g id=\"ink\" transform=\"translate(100 104) scale(%s %s) rotate(0 0 0)\">", is, is
      for (i = 1; i <= 3; i++)
        printf "<circle id=\"box%d\" cx=\"-34\" cy=\"%d\" r=\"10\" fill=\"url(#inkG)\" fill-opacity=\"%s\" stroke=\"url(#inkG)\" stroke-opacity=\"%s\" stroke-width=\"5\"/>", i, (i - 2) * 30, f2(iO * boxF), f2(iO)
      printf "<path id=\"ticks\" d=\"M -39 -30 L -35.5 -26.5 L -28.5 -34 M -39 0 L -35.5 3.5 L -28.5 -4 M -39 30 L -35.5 33.5 L -28.5 26\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"3.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", f2(iO * tickO)
      printf "<path id=\"lines\" d=\"M -12 -30 L 42 -30 M -12 0 L 30 0 M -12 30 L 36 30\" fill=\"none\" stroke=\"url(#inkG)\" stroke-opacity=\"%s\" stroke-width=\"8\" stroke-linecap=\"round\"/>", f2(iO * lineO)
      printf "<line id=\"slashGlow\" x1=\"-52\" y1=\"52\" x2=\"%d\" y2=\"%d\" stroke=\"#FF375F\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linecap=\"round\"/>", sx2, sy2, f2(iO * slashO * 0.25)
      printf "<line id=\"slash\" x1=\"-52\" y1=\"52\" x2=\"%d\" y2=\"%d\" stroke=\"#FF375F\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\"/>", sx2, sy2, f2(iO * slashO)
      printf "</g>"

      printf "<g id=\"card\" transform=\"translate(0 %d)\">", cardY
      printf "<text id=\"count\" x=\"18\" y=\"36\" font-size=\"46\" font-weight=\"700\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", f2(liveO), show(live ? ns : "")
      printf "<rect id=\"pill\" x=\"%s\" y=\"19\" width=\"%s\" height=\"34\" rx=\"17\" fill=\"#FF375F\" fill-opacity=\"%s\"/>", f2(px), f2(pw), f2(pillO * 0.2)
      printf "<circle id=\"clock\" cx=\"%s\" cy=\"36\" r=\"8\" fill=\"none\" stroke=\"#FF5C80\" stroke-opacity=\"%s\" stroke-width=\"2.5\"/>", f2(cx), f2(pillO)
      printf "<path id=\"hands\" d=\"M %s 31.5 L %s 36 L %s 38.5\" fill=\"none\" stroke=\"#FF5C80\" stroke-opacity=\"%s\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", f2(cx), f2(cx), f2(cx + 3.5), f2(pillO)
      printf "<text id=\"late\" x=\"%s\" y=\"37\" font-size=\"24\" font-weight=\"700\" dominant-baseline=\"middle\" fill=\"#FF5C80\" fill-opacity=\"%s\">%s</text>", f2(px + 31), f2(pillO), show(hot ? ls : "")
      printf "<line id=\"rule\" x1=\"18\" y1=\"64\" x2=\"182\" y2=\"64\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>", f2(liveO * 0.12)
      for (i = 1; i <= 3; i++) {
        printf "<circle id=\"dot%d\" cx=\"26\" cy=\"%s\" r=\"7\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"3\"/>", i, f2(TY[i]), DC[i], f2(RO[i])
        printf "<text id=\"title%d\" x=\"42\" y=\"%s\" font-size=\"18\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", i, f2(TY[i]), f2(RO[i]), show(T[i])
        printf "<text id=\"when%d\" x=\"42\" y=\"%d\" font-size=\"16\" font-weight=\"600\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", i, WY[i], WC[i], f2(WO[i]), show(RL[i])
      }
      printf "</g>"
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  reminders_frame "$@"
  exit 0
fi

api="http://127.0.0.1:9848"
cell="{{CELL_ID}}"
dir="$DESMAPTIC_STORAGE/gallery/$cell"          # state: "settings" while there is no access (for the tap), else empty
zf_mkdir -p "$dir" 2>/dev/null

# The reminders reader: one JavaScript for Automation process that reads EventKit, so the stock osascript is all it
# needs. It prints a block when it starts, when Reminders changes (EventKit's change notification, at most one read
# every 5 s), every minute (an item's time passes and it turns overdue) and after midnight:
#   !ok <due> <overdue> | !ask (waiting for the answer to the access question) | !denied <status> | !error <what>
#   <o|t>|<time or date>|<list colour>|<title>   … the first three, overdue first, then today's by time, then all-day
#   --
# It ends by itself after three hours; the loop below starts a fresh one while the button is on screen.
read -r -d '' reader_js <<'JXA'
ObjC.import("Foundation");
ObjC.import("AppKit");
ObjC.import("EventKit");

const REMINDER = 1;                                   // EKEntityTypeReminder
const NOT_DETERMINED = 0, FULL_ACCESS = 3;            // EKAuthorizationStatus
const out = $.NSFileHandle.fileHandleWithStandardOutput;
const err = $.NSFileHandle.fileHandleWithStandardError;
function put(handle, text) {
  const data = $(text).dataUsingEncodingAllowLossyConversion($.NSUTF8StringEncoding, true);
  if (!data.isNil()) handle.writeData(data);
}
function block(lines) { put(out, lines.join("\n") + "\n--\n"); }
function access() { return Number($.EKEventStore.authorizationStatusForEntityType(REMINDER)); }
function text(value) {
  try { const s = ObjC.unwrap(value); return (typeof s === "string") ? s : ""; } catch (e) { return ""; }
}
function clean(s) {
  return Array.from(s.replace(/[\u0000-\u001f\u007f\u2028\u2029|]+/g, " ").replace(/\s+/g, " ").trim()).slice(0, 120).join("");
}
function colourOf(reminder) {
  try {
    const c = reminder.calendar.color.colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
    if (c.isNil()) return "";
    const h = x => { const n = Math.round(Math.max(0, Math.min(1, Number(x))) * 255); return (n < 16 ? "0" : "") + n.toString(16).toUpperCase(); };
    return "#" + h(c.redComponent) + h(c.greenComponent) + h(c.blueComponent);
  } catch (e) { return ""; }
}

// The run loop waits for EventKit's notifications and answers; a port keeps it from returning at once.
const loop = $.NSRunLoop.currentRunLoop;
loop.addPortForMode($.NSMachPort.port, $.NSDefaultRunLoopMode);
function pump(seconds) {
  loop.runModeBeforeDate($.NSDefaultRunLoopMode, $.NSDate.dateWithTimeIntervalSinceNow(Math.max(0.05, seconds)));
}

const clock = $.NSDateFormatter.alloc.init;           // 24-hour time: digits in every language
clock.setLocale($.NSLocale.localeWithLocaleIdentifier("en_US_POSIX"));
clock.setDateFormat("HH:mm");
const day = $.NSDateFormatter.alloc.init;             // day and month in the order of the Mac's region: 25.09, 9/25
day.setLocale($.NSLocale.currentLocale);
day.setLocalizedDateFormatFromTemplate("dM");

// Every open reminder due before the end of today, from every list: [{e, allDay, late, colour, title, label}].
function read(store) {
  const calendar = $.NSCalendar.currentCalendar;
  const now = $.NSDate.date, nowS = Number(now.timeIntervalSince1970);
  const start = calendar.startOfDayForDate(now), startS = Number(start.timeIntervalSince1970);
  const end = calendar.dateByAddingUnitValueToDateOptions(16 /* NSCalendarUnitDay */, 1, start, 0);
  const endS = Number(end.timeIntervalSince1970);
  // Every reminders list, named explicitly: the bridge turns a JavaScript null into NSNull, not nil.
  const predicate = store.predicateForIncompleteRemindersWithDueDateStartingEndingCalendars(
    $.NSDate.distantPast, end, store.calendarsForEntityType(REMINDER));
  let found = null, done = false;
  // The answer comes on an EventKit queue; the block only keeps it, the work is done here.
  const request = store.fetchRemindersMatchingPredicateCompletion(predicate, function (reminders) { found = reminders; done = true; });
  for (let t = 0; t < 300 && !done; t++) pump(0.05);
  if (!done) { store.cancelFetchRequest(request); throw "no answer from EventKit"; }
  const count = (found === null || found === undefined || found.isNil()) ? 0 : Number(found.count);
  const list = [];
  for (let i = 0; i < count; i++) {
    const r = found.objectAtIndex(i);
    const due = r.dueDateComponents;
    if (due.isNil()) continue;
    let zone = calendar;
    if (!due.timeZone.isNil()) { zone = calendar.copy; zone.setTimeZone(due.timeZone); }
    const date = zone.dateFromComponents(due);
    if (date.isNil()) continue;
    const hour = Number(due.hour);
    const allDay = !(hour >= 0 && hour < 24);         // NSDateComponentUndefined: a date without a time
    const e = allDay ? Number(calendar.startOfDayForDate(date).timeIntervalSince1970) : Number(date.timeIntervalSince1970);
    if (!(e < endS)) continue;                          // tomorrow's all-day reminder starts where today ends
    const late = allDay ? e < startS : e < nowS;
    const label = e >= startS ? (allDay ? "" : text(clock.stringFromDate(date))) : text(day.stringFromDate(date));
    list.push({ e: e, allDay: allDay, late: late, colour: colourOf(r), title: clean(text(r.title)) || "—", label: label });
  }
  return list;
}
// The block for what was read: late ones may have turned overdue since.
function compose(list) {
  const nowS = Date.now() / 1000;
  const startS = Number($.NSCalendar.currentCalendar.startOfDayForDate($.NSDate.date).timeIntervalSince1970);
  for (const x of list) x.late = x.allDay ? x.e < startS : x.e < nowS;
  const rank = x => x.late ? 0 : (x.allDay ? 2 : 1);
  list.sort((a, b) => (rank(a) - rank(b)) || (a.e - b.e) || (a.title < b.title ? -1 : a.title > b.title ? 1 : 0));
  const late = list.filter(x => x.late).length;
  return ["!ok " + list.length + " " + late].concat(list.slice(0, 3).map(x => [x.late ? "o" : "t", x.label, x.colour, x.title].join("|")));
}

// Asked once per run, and only when macOS has never been answered: the question is about the agent.
if (access() === NOT_DETERMINED) {
  block(["!ask"]);
  const asker = $.EKEventStore.alloc.init;
  const answered = function (granted, error) {};
  try { asker.requestFullAccessToRemindersWithCompletion(answered); }
  catch (e) {
    try { asker.requestAccessToEntityTypeCompletion(REMINDER, answered); }
    catch (e2) { put(err, "reminders: cannot ask for access to Reminders: " + e2 + "\n"); }
  }
  for (let t = 0; t < 600 && access() === NOT_DETERMINED; t++) { pump(1); if (t % 60 == 59) block(["!ask"]); }
}

const started = Date.now();
let store = null, dirty = true, readAt = 0, list = [], today = "", shown = -1, failures = 0;
while (Date.now() - started < 3 * 3600 * 1000) {
  const status = access();
  if (status !== FULL_ACCESS) { block([status === NOT_DETERMINED ? "!ask" : "!denied " + status]); dirty = true; pump(30); continue; }
  if (store === null) {
    store = $.EKEventStore.alloc.init;
    // Any change to reminders — here, on the phone through iCloud, in another app — and a change of access.
    $.NSNotificationCenter.defaultCenter.addObserverForNameObjectQueueUsingBlock(
      $.EKEventStoreChangedNotification, store, $.NSOperationQueue.mainQueue, function (note) { dirty = true; });
  }
  const now = Date.now();
  const key = text(day.stringFromDate($.NSDate.date));
  if (key !== today) { today = key; dirty = true; }
  let fresh = false;
  if ((dirty && now - readAt >= 5000) || now - readAt >= 300000) {
    try { list = read(store); failures = 0; fresh = true; }
    catch (e) { failures++; block(["!error " + e]); if (failures >= 3) break; }
    readAt = now; dirty = false;
  }
  const minute = Math.floor(now / 60000);
  if (fresh || minute !== shown) { block(compose(list)); shown = minute; }
  const toMinute = 60.2 - (now / 1000) % 60;
  pump(dirty ? Math.min(toMinute, Math.max(0.2, (readAt + 5000 - now) / 1000)) : toMinute);
}
void 0;   // osascript would print a result
JXA

start_reader() {
  coproc /usr/bin/osascript -l JavaScript -e "$reader_js"
  reader=$! started=$EPOCHSECONDS heard=$EPOCHSECONDS
}
stop_reader() {
  (( reader )) && kill $reader 2>/dev/null
  reader=0
  lines=()
}

hidden=1 looked=0
post() {   # $1 frame → 0 when the agent took it; hidden=1 when the phone does not show the button
  local p=$1 out code body
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"duration\":0.8}}")
  code=${out##*$'\n'} body=${out%$'\n'*}
  if [[ $code != 200 ]]; then
    print -ru2 -- "reminders: update-button answered ${code:-nothing}: ${body[1,300]}"
    return 1
  fi
  looked=$EPOCHSECONDS
  [[ ${body//[[:space:]]/} == *'"visible":false'* ]] && hidden=1 || hidden=0
  return 0
}
on_screen() {   # does the phone show the button (or is it too old to say)?
  local out code body
  looked=$EPOCHSECONDS
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || { hidden=1; return 1 }
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  if [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]; then hidden=0; else hidden=1; fi
  (( ! hidden ))
}

typeset -a lines rows
# note starts unknown ("-"), so the first block always writes the state: a "settings" left by an earlier run, when access
# was denied, would otherwise keep the tap opening System Settings after access is granted.
perm="" said="" total=0 late=0 last="" sent=0 retry_at=0 note="-"

# The last block → perm (ok | ask | denied), total, late and rows.
take_block() {
  local line
  rows=()
  for line in "${lines[@]}"; do
    case $line in
      '!ok '*)
        perm=ok
        line=${line#!ok }
        total=${line%% *} late=${line##* }
        [[ $total == <-> && $late == <-> ]] || { total=0 late=0 }
        ;;
      '!ask') perm=ask ;;
      '!denied'*) perm=denied ;;
      '!error'*) print -ru2 -- "reminders: ${line#!error }" ;;
      [ot]'|'*) rows+=("$line") ;;
    esac
  done
  lines=()
  if [[ $perm == denied && $said != denied ]]; then
    print -ru2 -- "reminders: Allow the agent to access Reminders: System Settings → Privacy & Security → Reminders"
  fi
  said=$perm
  local want=""
  [[ $perm == denied ]] && want=settings
  if [[ $want != $note ]]; then
    print -r -- "$want" > "$dir/state.tmp" && zf_mv -f "$dir/state.tmp" "$dir/state" && note=$want
  fi
}

draw() {
  case $perm in
    ok)     frame=$(reminders_frame list $total $late "${rows[@]}") ;;
    denied) frame=$(reminders_frame denied) ;;
    ask)    frame=$(reminders_frame ask) ;;
    *)      frame=$(reminders_frame rest) ;;
  esac
}

while true; do
  if (( ! reader )); then
    # Nothing is read while the phone does not show the button: it is asked every 3 s.
    if (( EPOCHSECONDS >= retry_at )) && on_screen; then
      start_reader
      continue
    fi
    zselect -t 300
    continue
  fi

  t0=$EPOCHREALTIME
  if IFS= read -r -t 15 -p line; then
    if [[ $line != -- ]]; then lines+=("$line"); continue; fi
    heard=$EPOCHSECONDS
    take_block
    [[ -n $perm ]] || continue
    draw
    if [[ $frame != $last ]] || (( EPOCHSECONDS - sent >= 300 )); then   # on change, and a keyframe every 5 min
      if post "$frame"; then last=$frame sent=$EPOCHSECONDS; fi
      (( hidden )) && stop_reader
    fi
  elif ! kill -0 $reader 2>/dev/null || (( EPOCHREALTIME - t0 < 14.5 )); then
    # The reader ended: after three hours by itself (it starts again now), or early — then again in 30 s.
    if (( EPOCHSECONDS - started < 60 )); then
      print -ru2 -- "reminders: the reader stopped; starting it again in 30 s"
      retry_at=$(( EPOCHSECONDS + 30 ))
    fi
    stop_reader
    continue
  fi
  # The reader prints a block at least once a minute, and a read gives up after 15 s: silent for longer than that,
  # it is stuck (waiting on EventKit) — start a fresh one rather than keep showing what it read last.
  if (( reader && EPOCHSECONDS - heard > 150 )); then
    print -ru2 -- "reminders: the reader stopped answering; starting it again"
    stop_reader
    continue
  fi
  # A frame that did not change is not sent, so the phone is asked every 15 s whether it still shows the button.
  if (( reader && EPOCHSECONDS - looked >= 15 )); then
    on_screen || stop_reader
  fi
done
