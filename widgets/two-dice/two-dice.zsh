# Two dice: a tap throws two six-sided dice together and shows their sum, the throw of Monopoly and Catan.
# The whole throw is drawn here and posted frame by frame (about a second); nothing runs between taps.
# State, one line in gallery/<button>/state: "<die 1> <die 2> <angle of die 1> <angle of die 2>" — the last throw
# and how the dice lie, so the next throw starts exactly where they are.
#
# Try it without the phone:
#   zsh two-dice.zsh --face rest|demo[-landscape]   the button's resting face / the Gallery's sample, as SVG
#   DICE_DRY=1 zsh two-dice.zsh                     prints every frame of a throw instead of posting it
#   DICE_RESULT="<n> <n>" forces the result of a dry throw, DICE_SEED=<n> its look; a dry run keeps its state in
#   $DICE_STORAGE or a temp folder, never in the live storage, and never calls the agent
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/stat || { print -u2 -- "two dice: a zsh module is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm b:zf_rmdir || { print -u2 -- "two dice: zsh module files is missing"; exit 1 }

# ---- the face: one frame function draws every frame, in both layouts ------------------------------------------
# Every frame has the same elements in the same order, so the whole throw glides. The 2×1 face (400×200) has the
# dice side by side and the sum on the right; its turned twin (200×400, the button in landscape) stacks them.
#
# awk -v mode=throw|rest ... prints one line per frame: "<duration> <easing> <wait> <2×1 svg>\t<1×2 svg>",
# wait = seconds until the next frame is posted (less than the duration in flight: the next frame takes over the
# glide mid-way and the spin never stops; equal to it on the table: every short move plays to its end).
read -r -d '' dice_awk <<'AWK'
function hexv(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
function mix(a, b, t,   i, o, x, y) {
  o = "#"
  for (i = 2; i <= 6; i += 2) { x = hexv(substr(a, i, 2)); y = hexv(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
  return o
}
function f(x) { x = sprintf("%.1f", x); return x == "-0.0" ? "0.0" : x }
function pt(x, y) { return f(x) "," f(y) }
function norm(a) { while (a > 180) a -= 360; while (a <= -180) a += 360; return a }

# A die's outline: a square of half side s with corners rounded by r, always M L C L C L C L C Z.
function rsq(s, r,   a, c) {
  a = s - r; c = s - r * (1 - K)
  return "M" pt(-a, -s) "L" pt(a, -s) "C" pt(c, -s) " " pt(s, -c) " " pt(s, -a) \
    "L" pt(s, a) "C" pt(s, c) " " pt(c, s) " " pt(a, s) \
    "L" pt(-a, s) "C" pt(-c, s) " " pt(-s, c) " " pt(-s, a) \
    "L" pt(-s, -a) "C" pt(-s, -c) " " pt(-c, -s) " " pt(-a, -s) "Z"
}

# Where a die stands on the table in a layout: along the row (x in the 2×1, y in the 1×2) and across it.
function tablexy(i, lay,   al, cr) {
  al = REST[i] + SHIFT[lay] + DA[i]; cr = CROSS[lay] + DC[i]
  if (lay == "p") { TXY_X = al; TXY_Y = cr } else { TXY_X = cr; TXY_Y = al }
}

# One frame in layout lay (p = 2×1, l = 1×2) from the globals. Die i (1, 2): V value, BL blank (1 = in flight:
# all seven pips dimmed alike), H height over the table (0..1), ANG degrees, SX/SY squash, WV/WO the ring a landing
# sends over the table (0 at the die's edge .. 1 a little further out, and its opacity), DA/DC how far it has
# drifted from its place along and across the row. The sum: SUM, SUMO opacity, SUMFS size, GOLD 0..1 (doubles).
function frame(lay,   i, k, out, sc, on, pr, pc, po, vw, vh, gx, gy) {
  vw = lay == "p" ? 400 : 200; vh = lay == "p" ? 200 : 400
  gx = lay == "p" ? 330 : 100; gy = lay == "p" ? 100 : 318
  out = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 " vw " " vh "'><defs>"
  out = out "<linearGradient id='gb' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#ECE5D8'/><stop offset='1' stop-color='#B4A893'/></linearGradient>"
  out = out "<linearGradient id='gf' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#FFFFFF'/><stop offset='1' stop-color='#EAE2D3'/></linearGradient>"
  out = out "<radialGradient id='gg' cx='0.5' cy='0.5' r='0.5'><stop offset='0' stop-color='#FFD60A' stop-opacity='0.75'/><stop offset='0.6' stop-color='#FFD60A' stop-opacity='0.22'/><stop offset='1' stop-color='#FFD60A' stop-opacity='0'/></radialGradient></defs>"
  # the light behind the sum when both dice show the same number
  out = out "<circle id='glow' cx='" f(gx) "' cy='" f(gy) "' r='74' fill='url(#gg)' opacity='" sprintf("%.2f", 0.6 * GOLD) "'/>"
  for (i = 1; i <= 2; i++) {
    tablexy(i, lay)
    out = out "<path id='s" i "' d='" OUTLINE "' fill='#000000' opacity='" sprintf("%.2f", 0.42 - 0.24 * (H[i] > 0 ? H[i] : 0)) \
      "' transform='translate(" f(TXY_X + 4 + 12 * H[i]) " " f(TXY_Y + 7 + 14 * H[i]) ") rotate(" f(norm(ANG[i])) " 0 0) scale(" \
      sprintf("%.3f %.3f", SX[i] * (1 - 0.04 * H[i]), SY[i] * (1 - 0.04 * H[i])) ")'/>"
  }
  for (i = 1; i <= 2; i++) {
    tablexy(i, lay)
    out = out "<circle id='w" i "' cx='" f(TXY_X) "' cy='" f(TXY_Y) "' r='" f(1.2 * S + 20 * WV[i]) "' fill='none' stroke='#FFFFFF' stroke-width='" \
      f(6 - 5 * WV[i]) "' opacity='" sprintf("%.2f", WO[i]) "'/>"
  }
  for (i = 1; i <= 2; i++) {
    tablexy(i, lay)
    sc = 1 + LIFTSCALE * H[i]                   # higher = closer to the camera above the table
    out = out "<g id='d" i "' transform='translate(" f(TXY_X) " " f(TXY_Y - 3 * H[i]) ") rotate(" f(norm(ANG[i])) " 0 0) scale(" \
      sprintf("%.3f %.3f", sc * SX[i], sc * SY[i]) ")'>"
    out = out "<path id='b" i "' d='" OUTLINE "' fill='url(#gb)'/>"
    out = out "<path id='t" i "' d='" TOPLINE "' fill='url(#gf)'/>"
    # pips: 0 top left, 1 top right, 2 middle left, 3 centre, 4 middle right, 5 bottom left, 6 bottom right
    for (k = 0; k < 7; k++) {
      on = index(PIPS[V[i]], k) > 0
      pr = PR; pc = "#26262E"; po = BL[i] ? 0.18 : on
      if (!BL[i] && V[i] == 1 && k == 3) { pr = PR1; pc = "#D7263D" }   # the single pip: big and red
      out = out "<circle id='p" i k "' cx='" f(PX[k]) "' cy='" f(PY[k]) "' r='" f(pr) "' fill='" pc "' opacity='" sprintf("%.2f", po) "'/>"
    }
    out = out "</g>"
  }
  out = out "<text id='sum' x='" f(gx) "' y='" f(gy) "' font-size='" f(SUMFS) "' font-weight='bold' text-anchor='middle' dominant-baseline='middle' fill='" \
    mix("#FFFFFF", "#FFD60A", GOLD) "' opacity='" sprintf("%.2f", SUMO) "'>" SUM "</text>"
  return out "</svg>"
}

function die(i, val, blank, h, ang, sx, sy, wave, waveo, da, dc) {
  V[i] = val; BL[i] = blank; H[i] = h; ANG[i] = ang; SX[i] = sx; SY[i] = sy; WV[i] = wave; WO[i] = waveo; DA[i] = da; DC[i] = dc
}
function face(sum, o, fs, gold) { SUM = sum; SUMO = o; SUMFS = fs; GOLD = gold }
function emit(dur, easing, wait) { printf "%.3f %s %.3f %s\t%s\n", dur, easing, wait, frame("p"), frame("l") }

# Die i on the table at stage st of its landing: 1 impact, 2 bounce, 3 second touch, 4 and on at rest.
function landing(i, st) {
  if (st == 1) die(i, NEW[i], 0, 0, LEAN[i], 1.1, 0.88, 0.15, 0.5, 0, 0)
  else if (st == 2) die(i, NEW[i], 0, 0.14, LEAN[i] + (RESTA[i] - LEAN[i]) * 0.65, 0.97, 1.04, 1, 0, 0, 0)
  else if (st == 3) die(i, NEW[i], 0, 0, RESTA[i], 1.035, 0.965, 1, 0, 0, 0)
  else die(i, NEW[i], 0, 0, RESTA[i], 1, 1, 0, 0, 0, 0)
}

BEGIN {
  PI = atan2(0, -1); K = 0.55
  S = 44; RS = 13                               # a die: half its side, corner radius
  OUTLINE = rsq(S, RS); TOPLINE = rsq(0.9 * S, 0.85 * RS)
  LIFTSCALE = 0.08
  REST[1] = 74; REST[2] = 188                   # their places along the row; across it, the middle
  CROSS["p"] = 97; CROSS["l"] = 98
  SHIFT["p"] = 0; SHIFT["l"] = 6                # in the 1×2 a lifted die rises towards the top edge: start lower
  DRIFT[1] = -6; DRIFT[2] = 12                  # in the air they spread apart (all of it by half height), so two
                                                # spinning corners never meet
  FS = 92                                       # the sum
  d = 0.54 * S; PR = 0.2 * S; PR1 = 0.28 * S
  PX[0] = -d; PY[0] = -d; PX[1] = d; PY[1] = -d; PX[2] = -d; PY[2] = 0; PX[3] = 0; PY[3] = 0
  PX[4] = d; PY[4] = 0; PX[5] = -d; PY[5] = d; PX[6] = d; PY[6] = d
  PIPS[1] = "3"; PIPS[2] = "15"; PIPS[3] = "135"; PIPS[4] = "0156"; PIPS[5] = "01356"; PIPS[6] = "012456"

  if (mode == "rest") {
    die(1, a, 0, 0, ra, 1, 1, 0, 0, 0, 0); die(2, b, 0, 0, rb, 1, 1, 0, 0, 0, 0)
    face(a + b, 1, FS, a == b); emit(0, "easeInOut", 0); exit
  }

  # mode == "throw": pa pb the dice on the button now and pra prb the angles they lie at, a b the result, seed the
  # look of this throw (never its result). The first line out is "angles <die 1> <die 2>": where they will lie.
  srand(seed)
  OLD[1] = pa; OLD[2] = pb; NEW[1] = a; NEW[2] = b; PA[1] = pra; PA[2] = prb
  first = rand() < 0.5 ? 1 : 2                  # one die lands a moment before the other
  W[1] = 1.0; W[2] = 0.97; W[3] = 0.92; W[4] = 0.85; W[5] = 0.76; W[6] = 0.64; W[7] = 0.52
  for (i = 1; i <= 2; i++) {
    DIR[i] = rand() < 0.5 ? 1 : -1              # spin direction
    TILT[i] = 4 + int(rand() * 7)               # how far it leans when it lands
    LIFT[i] = int(rand() * 16)                  # how high it flies
    DC[i] = 0; WOB[i] = int(rand() * 17) - 8    # a little sideways drift in the air
    FLY[i] = i == first ? 6 : 7                 # frames in the air
    sw = 0; for (k = 1; k <= FLY[i]; k++) sw += W[k]
    SW[i] = sw
    # From the wind-up to 6 degrees short of the lean it lands with, turning DIR: about two turns, the later die a
    # little more, and never 150 degrees or more a frame (from 180 on the phone turns it back the short way). A
    # quarter turn more or less still shows the same face, so the landing picks one that fits.
    from = PA[i] - DIR[i] * 10; base = DIR[i] * (TILT[i] - 6)
    turn0 = (base - from) * DIR[i]; while (turn0 < 0) turn0 += 360; while (turn0 >= 360) turn0 -= 360
    lo = FLY[i] == 6 ? 560 : 640; hi = 149 * sw / W[1]
    n = 0; for (j = 0; j < 12; j++) if (turn0 + 90 * j >= lo && turn0 + 90 * j <= hi) C[++n] = j
    j = C[1 + int(rand() * n)]
    TURN[i] = turn0 + 90 * j; A[i] = from
    LEAN[i] = from + DIR[i] * (TURN[i] + 6)
    RESTA[i] = LEAN[i] - DIR[i] * TILT[i] + int(rand() * 9) - 4   # and lies a few degrees askew, as real dice do
    LIES[i] = norm(RESTA[i])
  }
  printf "angles %d %d\n", LIES[1], LIES[2]
  psum = pa + pb; sum = a + b; dbl = a == b

  # wind-up: both dice squash in the hand, their faces blank; the old sum dims and keeps its number until they land
  for (i = 1; i <= 2; i++) die(i, OLD[i], 1, -0.06, A[i], 1.05, 0.93, 0, 0, 0, 0)
  face(psum, 0.25, FS, 0); emit(0.12, "easeInOut", 0.11)
  # frames 1-6 in the air for both, 7 lands the first die, 8 the second (and shows the sum), then they settle
  DUR[7] = 0.08; DUR[8] = 0.1; DUR[9] = 0.13; DUR[10] = 0.1; DUR[11] = 0.16
  for (k = 1; k <= 11; k++) {
    for (i = 1; i <= 2; i++) {
      if (k <= FLY[i]) {
        A[i] += DIR[i] * TURN[i] * W[k] / SW[i]
        u = k / (FLY[i] + 1); h = (0.85 + LIFT[i] / 100) * 4 * u * (1 - u)
        die(i, OLD[i], 1, h, A[i], 1, 1, 0, 0, DRIFT[i] * (h < 0.5 ? 2 * h : 1), WOB[i] * h)
      } else landing(i, k - FLY[i])
    }
    if (k <= 7) face(psum, 0.25, FS, 0)
    else if (k == 8) face(sum, 1, FS * 1.1, dbl * 0.5)
    else face(sum, 1, FS, dbl)
    if (k <= 6) emit(0.1, "linear", 0.092)
    else emit(DUR[k], "easeInOut", k == 11 ? 0 : DUR[k])
  }
}
AWK

# ---- the faces item.json ships: zsh two-dice.zsh --face rest|demo[-landscape] ---------------------------------
if (( $# )); then
  case "$1 ${2:-}" in
    "--face rest"|"--face rest-landscape") face=( -v a=3 -v b=4 -v ra=-3 -v rb=4 ) ;;
    "--face demo"|"--face demo-landscape") face=( -v a=5 -v b=5 -v ra=4 -v rb=-2 ) ;;
    *) print -u2 -- "usage: zsh two-dice.zsh --face rest|rest-landscape|demo|demo-landscape"; exit 2 ;;
  esac
  awk -v mode=rest $face "$dice_awk" | {
    IFS=' ' read -r _ _ _ svgs
    if [[ $2 == *-landscape ]]; then print -r -- "${svgs#*$'\t'}"; else print -r -- "${svgs%%$'\t'*}"; fi
  }
  exit 0
fi

# ---- the button --------------------------------------------------------------------------------------------
cell="{{CELL_ID}}"
dry=0
[[ -n ${DICE_DRY:-} ]] && dry=1
if (( dry )); then
  dir="${DICE_STORAGE:-${TMPDIR:-/tmp}/two-dice-dry-$UID}/gallery/$cell"     # never the live storage
else
  [[ -n ${DESMAPTIC_TOKEN:-} ]] || { print -u2 -- "two dice: not started by Desmaptic Agent (no DESMAPTIC_TOKEN); try DICE_DRY=1"; exit 1 }
  dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
fi
state_file=$dir/state
lock=$dir/busy

# One throw at a time: a tap while the dice are still moving is ignored, so two animations never mix. A lock older
# than 20 s was left by a script that was stopped: it is taken over.
zf_mkdir -p -- $dir 2>/dev/null
if ! zf_mkdir -- $lock 2>/dev/null; then
  typeset -a mtime
  zstat -A mtime +mtime -- $lock 2>/dev/null && (( EPOCHSECONDS - mtime[1] < 20 )) && exit 0
  zf_rmdir -- $lock 2>/dev/null
  zf_mkdir -- $lock 2>/dev/null || { print -u2 -- "two dice: cannot write in $dir"; exit 1 }
fi
trap 'zf_rmdir -- $lock 2>/dev/null' EXIT
trap 'exit 0' TERM INT

# The state, read field by field (never sourced); anything unreadable is the resting face: 3 and 4, at -3 and 4
# degrees.
last1=3 last2=4 angle1=-3 angle2=4
line=""
{ IFS= read -r line < $state_file } 2>/dev/null
fields=( ${=line} )
[[ $fields[1] == [1-6] && $fields[2] == [1-6] && $fields[3] == (-|)<0-180> && $fields[4] == (-|)<0-180> ]] &&
  last1=$fields[1] last2=$fields[2] angle1=$fields[3] angle2=$fields[4]

# Replaces the state file in one step, so a reader never sees half a line.
write_state() {
  { print -r -- "$*" > "$state_file.$$" } 2>/dev/null &&
    zf_mv -f -- "$state_file.$$" $state_file 2>/dev/null ||
    { zf_rm -f -- "$state_file.$$" 2>/dev/null; print -u2 -- "two dice: cannot write in $dir"; return 1 }
}

# post <svg> <landscape svg> <duration> <easing>: one frame to the button. The SVG has single-quoted attributes and
# only digits as text, so it goes into the JSON as it is. The token goes from the environment into the request by
# curl itself.
post() {
  local code
  code=$(curl -q -s -m 3 -o /dev/null -w '%{http_code}' \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:9848/api/update-button \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$1\",\"landscapeSource\":\"$2\",\"duration\":$3,\"easing\":\"$4\"}}")
  [[ $code == 200 ]] && return 0
  print -u2 -- "two dice: the agent answered ${code:-nothing}"
  return 1
}

# play <frames>: posts each line of the frame function on time. A frame's wait is counted from the moment it was
# posted, so a slow post shifts the rest of the throw instead of cutting a glide short. DICE_DRY prints the lines.
play() {
  local line dur easing gap svgs
  typeset -F next=0 sent
  integer cs
  for line in "${(@f)1}"; do
    dur=${line%% *}; line=${line#* }; easing=${line%% *}; line=${line#* }; gap=${line%% *}; svgs=${line#* }
    [[ $dur == <->.<-> && $gap == <->.<-> && $svgs == '<svg '*$'\t<svg '* ]] || { print -u2 -- "two dice: a frame did not come out"; return 1 }
    if (( dry )); then print -r -- "$dur $easing $gap $svgs"; continue; fi
    # zselect waits whole hundredths of a second; the last few milliseconds are counted out here, because in
    # flight a frame has only 8 ms to spare before the glide it takes over would stop
    (( cs = (next - EPOCHREALTIME) * 100 ))
    (( cs > 0 )) && zselect -t $cs
    while (( EPOCHREALTIME < next )); do :; done
    sent=$EPOCHREALTIME
    post "${svgs%%$'\t'*}" "${svgs#*$'\t'}" $dur $easing || return 1
    (( next = sent + gap ))
  done
}

# roll1, roll2 = two fair numbers from 1 to 6, and style = 32 more random bits for the throw's look. The kernel's
# random bytes, the uneven top of their range thrown away, so every face comes up exactly as often as any other.
draw() {
  local -a words
  integer limit=$(( 4294967296 - 4294967296 % 6 )) tries
  for (( tries = 0; tries < 8; tries++ )); do
    words=( $(od -An -N12 -tu4 /dev/urandom 2>/dev/null) )
    [[ $words[1] == <-> && $words[2] == <-> && $words[3] == <-> ]] || break
    (( words[1] < limit && words[2] < limit )) || continue
    roll1=$(( words[1] % 6 + 1 )) roll2=$(( words[2] % 6 + 1 )) style=$words[3]
    return 0
  done
  print -u2 -- "two dice: no random numbers from the system"
  return 1
}

draw || exit 1
if (( dry )); then
  forced=( ${=DICE_RESULT:-} )
  [[ $forced[1] == [1-6] && $forced[2] == [1-6] ]] && roll1=$forced[1] roll2=$forced[2]
  [[ ${DICE_SEED:-} == <-> ]] && style=$DICE_SEED
fi
frames=$(awk -v mode=throw -v pa=$last1 -v pb=$last2 -v pra=$angle1 -v prb=$angle2 -v a=$roll1 -v b=$roll2 \
  -v seed=$style "$dice_awk")
angles=( ${=${${(f)frames}[1]}} )
[[ $angles[1] == angles && $angles[2] == (-|)<0-180> && $angles[3] == (-|)<0-180> ]] ||
  { print -u2 -- "two dice: a frame did not come out"; exit 1 }
write_state $roll1 $roll2 $angles[2] $angles[3] || exit 1
play "${frames#*$'\n'}" || exit 1
exit 0
