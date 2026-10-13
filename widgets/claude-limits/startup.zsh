#!/bin/zsh
# Claude Limits: how much of the Claude usage limits is used — the 5-hour window and the week — and when each resets
# (a 2×2 SVG face).
lang=""        # the words when there are no limits yet: en de es fr ru; empty — the Mac's first language, English for any other
#
# The numbers come from Claude Code itself: it passes `rate_limits` only to its status line, and the agent's status
# line (Desmaptic Agent → AI Assistants → Claude Code → Claude limits → Turn On) saves them to
# $DESMAPTIC_STORAGE/ClaudeLimits/<account>.json on every update of a Claude Code session:
# {"updated":<unix s>,"five_hour":{"used_percentage":23.5,"resets_at":<unix s>},"seven_day":{…}}. A window may be
# missing (a team plan has no seven_day); a window Claude Code dropped after its reset keeps its last values, with its
# reset time already past. Several accounts (CLAUDE_CONFIG_DIR) save a file each: the face shows the one updated last.
# This script only reads that file: no token, no network, nothing of Claude's own.
#
# Until the first numbers come the face says in words where to turn the status line on, in the Mac's language (the
# agent passes the script no phone language): no symbol says that.
# The file is read every 15 seconds; a frame goes out only when the face changes — the time left and the age of the
# numbers count by the minute. Numbers that stopped coming stay on the face with their age; a window whose reset time
# has passed shows ✓ instead of its percent, whatever it was.
#
# Every frame has the same 15 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|one|two> [age tag1 used1 left1 [tag2 used2 left2]]` prints one frame (rest.svg and
# demo.svg are made that way; `--face off <lang>` — the hint); `zsh startup.zsh --read <unix s>` prints the frame for
# the saved file at that time.
# CLAUDE_LIMITS_DRY=1 runs the loop but prints each frame ("frame: <svg>") instead of sending it.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# limits_frame <state> [age tag1 used1 left1 [tag2 used2 left2]]: the 2×2 face (200×200). A dial on top — the outer
# ring the first window's use, the inner ring the second's, a spark in the middle — and under it a column for each
# window: its length in its ring's colour ("5h", "7d"), the percent used (✓ once it reset), and "↻" with the time
# until it resets; at the bottom a clock with the age of the numbers. A ring turns yellow from 80 % and pink from
# 90 %; the age turns yellow after an hour without new numbers.
# rest: the dial alone, large (the face before the script runs); off <lang>: no saved limits yet — a grey dial and
# three lines on where to turn them on; one: one window; two: both. used: a whole percent, or r for a window that
# reset; left: "2h_10m" (an underscore for a space).
limits_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} age=${2:-0} g1=${3:-0} u1=${4:-0} t1=${5:-0} g2=${6:-0} u2=${7:-0} t2=${8:-0}
  [[ $state == (rest|off|one|two) ]] || state=rest
  local hint=en
  [[ $state == off && $age == (de|es|fr|ru) ]] && hint=$age
  [[ $age == <->[mhd] ]] || age=0
  [[ $g1 == (5h|7d) ]] || g1=0
  [[ $g2 == (5h|7d) ]] || g2=0
  [[ $u1 == (<->|r) ]] || u1=0
  [[ $u2 == (<->|r) ]] || u2=0
  [[ $u1 == <-> ]] && (( u1 > 100 )) && u1=100
  [[ $u2 == <-> ]] && (( u2 > 100 )) && u2=100
  t1=${t1//_/ } t2=${t2//_/ }
  [[ -n $t1 && $t1 != *[^0-9dhm\ ]* ]] || t1=0
  [[ -n $t2 && $t2 != *[^0-9dhm\ ]* ]] || t2=0
  awk -v st=$state -v hint=$hint -v age=$age -v g1=$g1 -v u1=$u1 -v t1="$t1" -v g2=$g2 -v u2=$u2 -v t2="$t2" '
    function f(x) { return sprintf("%.2f", x) }
    function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
    function em(s,   i, c, w) {                 # the width of a text in ems: the system font, digits monospaced
      w = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "%" || c == "m") w += 0.90; else if (c == " ") w += 0.27; else if (c ~ /[\303\320\321]/) w += 0.62
        else if (c ~ /[\300-\377]/) w += 1; else if (c !~ /[\200-\277]/) w += 0.62  # accented Latin and Cyrillic: a letter
      }
      return w
    }
    function fit(s, size, width) { return (em(s) * size > width) ? width / em(s) : size }
    function text(id, x, y, size, weight, fill, op, val, anchor) {
      printf "<text id=\"%s\" x=\"%s\" y=\"%s\" font-size=\"%s\" font-weight=\"%d\" text-anchor=\"%s\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", id, f(x), f(y), f(size), weight, (anchor == "" ? "middle" : anchor), fill, f(op), val
    }
    # heat: 0 calm, 1 from 80 % (yellow), 2 from 90 % (pink); a window that reset is calm
    function heat(u) { return (u == "r") ? 0 : (u >= 90) ? 2 : (u >= 80) ? 1 : 0 }
    BEGIN {
      two = (st == "two"); one = (st == "one"); live = one || two
      C1 = 439.82; C2 = 301.59                  # 2π·70 and 2π·48: the rings, in the dial own 200×200 units
      a1 = (live && u1 != "r") ? clamp(u1 / 100) * C1 : 0
      a2 = (two && u2 != "r") ? clamp(u2 / 100) * C2 : 0
      H1 = live ? heat(u1) : 0
      H2 = two ? heat(u2) : 0
      H = (H1 > H2) ? H1 : H2

      # each window keeps its own colours whichever ring it is on: 5h coral, 7d lavender
      c0["5h"] = "#FFB088"; c1["5h"] = "#D97757"; kc["5h"] = "#FFB088"
      c0["7d"] = "#C9B8FF"; c1["7d"] = "#8E7CFF"; kc["7d"] = "#B9A8FF"
      c0["0"] = "#FFB088"; c1["0"] = "#D97757"; kc["0"] = "#FFB088"
      split("- #FFE45C #FF8FA8", hot0, " "); split("- #FFD60A #FF375F", hot1, " "); split("- #FFE45C #FF7A96", hotK, " ")
      r10 = H1 ? hot0[H1 + 1] : c0[g1]; r11 = H1 ? hot1[H1 + 1] : c1[g1]; k1 = H1 ? hotK[H1 + 1] : kc[g1]
      x2 = (g2 == "0") ? "7d" : g2
      r20 = H2 ? hot0[H2 + 1] : c0[x2]; r21 = H2 ? hot1[H2 + 1] : c1[x2]; k2 = H2 ? hotK[H2 + 1] : kc[g2]
      o1 = live ? 1 : 0; h1 = live ? 0.22 + 0.06 * H1 : 0
      o2 = two ? 1 : 0;  h2 = two ? 0.20 + 0.06 * H2 : 0
      k1O = 0.12; k2O = (two || st == "rest") ? 0.12 : 0
      s0 = "#FFB088"; s1 = "#D97757"; sO = 0.95; sS = (two || st == "rest") ? 1 : 1.3
      split("#D97757 #FFD60A #FF375F", bc, " "); split("0.16 0.18 0.26", ba, " ")
      bC = bc[H + 1]; bA = ba[H + 1]; bM = bA * 0.35
      if (st == "off") { s0 = "#8E8E93"; s1 = "#AEAEB2"; sO = 0.5; bC = "#636366"; bA = 0; bM = 0; k1O = 0.10 }
      # the dial: large in the middle at rest, small on top otherwise
      if (st == "rest") { ds = 0.9; dy = 100 } else { ds = 0.48; dy = 50 }
      dx = 100 - 100 * ds; dy = dy - 100 * ds

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"ring1G\" gradientUnits=\"userSpaceOnUse\" x1=\"30\" y1=\"30\" x2=\"170\" y2=\"170\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", r10, r11
      printf "<linearGradient id=\"ring2G\" gradientUnits=\"userSpaceOnUse\" x1=\"52\" y1=\"52\" x2=\"148\" y2=\"148\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", r20, r21
      printf "<linearGradient id=\"sparkG\" gradientUnits=\"userSpaceOnUse\" x1=\"80\" y1=\"80\" x2=\"120\" y2=\"120\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", s0, s1
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", bC, f(bA), bC, f(bM), bC
      printf "<g id=\"dial\" transform=\"translate(%s %s) scale(%s)\">", f(dx), f(dy), f(ds)
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"90\" fill=\"url(#bloomG)\"/>"
      printf "<circle id=\"track1\" cx=\"100\" cy=\"100\" r=\"70\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"11\"/>", f(k1O)
      printf "<circle id=\"halo1\" cx=\"100\" cy=\"100\" r=\"70\" fill=\"none\" stroke=\"url(#ring1G)\" stroke-opacity=\"%s\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(h1), f(a1), f(C1)
      printf "<circle id=\"arc1\" cx=\"100\" cy=\"100\" r=\"70\" fill=\"none\" stroke=\"url(#ring1G)\" stroke-opacity=\"%s\" stroke-width=\"11\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(o1), f(a1), f(C1)
      printf "<circle id=\"track2\" cx=\"100\" cy=\"100\" r=\"48\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"9\"/>", f(k2O)
      printf "<circle id=\"halo2\" cx=\"100\" cy=\"100\" r=\"48\" fill=\"none\" stroke=\"url(#ring2G)\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(h2), f(a2), f(C2)
      printf "<circle id=\"arc2\" cx=\"100\" cy=\"100\" r=\"48\" fill=\"none\" stroke=\"url(#ring2G)\" stroke-opacity=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(o2), f(a2), f(C2)
      printf "<path id=\"spark\" d=\"M 100 82 L 100 118 M 82 100 L 118 100 M 87.27 87.27 L 112.73 112.73 M 87.27 112.73 L 112.73 87.27\" fill=\"none\" stroke=\"url(#sparkG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\" transform=\"translate(100 100) scale(%s) translate(-100 -100)\"/>", f(sO), f(sS)
      printf "</g>"

      # the texts, in this order in every frame: tag1 used1 left1 tag2 used2 left2, then the age. Hidden ones keep a "0"
      # (an empty <text> would change the structure). A window that reset shows a green ✓ and "↻" alone.
      v1 = (u1 == "r") ? "✓" : u1 "%"; v2 = (u2 == "r") ? "✓" : u2 "%"
      w1 = (u1 == "r") ? "↻" : "↻" t1; w2 = (u2 == "r") ? "↻" : "↻" t2
      p1O = 0; l1O = 0; p2O = 0; l2O = 0; q1O = 0; q2O = 0; aO = 0
      p1C = "#FFFFFF"; p2C = "#FFFFFF"; aC = "#FFFFFF"
      if (!live) { v1 = "0"; w1 = "0"; v2 = "0"; w2 = "0"; g1 = "0"; g2 = "0"; age = "0" }
      if (one) { v2 = "0"; w2 = "0"; g2 = "0" }
      if (live) {
        p1O = 1; l1O = 0.72; q1O = (g1 == "0") ? 0 : 0.95; if (H1) p1C = k1; if (u1 == "r") p1C = "#30D158"
        aO = 0.6; if (age ~ /h$/ || age ~ /d$/) { aC = "#FFE45C"; aO = 0.9 }
      }
      if (two) { p2O = 1; l2O = 0.72; q2O = (g2 == "0") ? 0 : 0.95; if (H2) p2C = k2; if (u2 == "r") p2C = "#30D158" }
      if (st == "off") {                        # where to turn it on, in three lines; the window texts hidden
        split("Turn on in|Desmaptic Agent|AI Assistants", h, "|")
        if (hint == "de") split("Einschalten in|Desmaptic Agent|KI-Assistenten", h, "|")
        if (hint == "es") split("Actívalo en|Desmaptic Agent|Asistentes de IA", h, "|")
        if (hint == "fr") split("À activer dans|Desmaptic Agent|Assistants IA", h, "|")
        if (hint == "ru") split("Включите в|Desmaptic Agent|ИИ-ассистенты", h, "|")
        text("tag1", 100, 116, fit(h[1], 19, 176), 600, "#AEAEB2", 0.9, h[1])
        text("used1", 100, 142, fit(h[2], 21, 176), 700, "#FFFFFF", 0.85, h[2])
        text("left1", 100, 168, fit(h[3], 19, 176), 600, "#AEAEB2", 0.9, h[3])
        text("tag2", 148, 104, 18, 700, k2, 0, g2)
        text("used2", 148, 130, 30, 700, p2C, 0, v2)
        text("left2", 148, 156, 17, 600, "#FFFFFF", 0, w2)
      } else if (two) {                         # a column under each side of the dial
        text("tag1", 52, 104, 18, 700, k1, q1O, g1)
        text("used1", 52, 130, fit(v1, 30, 80), 700, p1C, p1O, v1)
        text("left1", 52, 156, fit(w1, 17, 80), 600, "#FFFFFF", l1O, w1)
        text("tag2", 148, 104, 18, 700, k2, q2O, g2)
        text("used2", 148, 130, fit(v2, 30, 80), 700, p2C, p2O, v2)
        text("left2", 148, 156, fit(w2, 17, 80), 600, "#FFFFFF", l2O, w2)
      } else {                                  # one column in the middle
        text("tag1", 100, 104, 20, 700, k1, q1O, g1)
        text("used1", 100, one ? 134 : 146, fit(v1, 40, 160), 700, p1C, p1O, v1)
        text("left1", 100, 164, fit(w1, 19, 160), 600, "#FFFFFF", l1O, w1)
        text("tag2", 148, 104, 18, 700, k2, 0, g2)
        text("used2", 148, 130, 30, 700, p2C, 0, v2)
        text("left2", 148, 156, 17, 600, "#FFFFFF", 0, w2)
      }
      # the age of the numbers: a clock and "3m", centred together at the bottom
      x0 = 100 - (14 + 5 + em(age) * 15) / 2
      printf "<circle id=\"clock\" cx=\"%s\" cy=\"185\" r=\"6\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"1.8\"/>", f(x0 + 7), aC, f(aO)
      printf "<path id=\"hands\" d=\"M %s 181.5 L %s 185 L %s 186.8\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", f(x0 + 7), f(x0 + 7), f(x0 + 9.6), aC, f(aO)
      text("age", x0 + 19, 185, 15, 600, aC, aO, age, "start")
      printf "</svg>\n"
    }'
}

# MARK: - The saved limits

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Claude limits: zsh modules datetime/zselect are missing"; exit 1 }

# REPLY = a time span as the face writes it, $2 = up (time left, rounded up) or down (an age, rounded down): 45m,
# 2h 10m (below 10 hours, by the minute), 23h, 5d 3h (below 10 days), 23d; an age: 3m, 2h, 4d.
span_text() {
  emulate -L zsh
  local -i s=$1 m
  (( s < 0 )) && s=0
  if [[ $2 == down ]]; then
    if (( s < 3600 )); then REPLY="$(( s / 60 ))m"
    elif (( s < 86400 )); then REPLY="$(( s / 3600 ))h"
    else REPLY="$(( s / 86400 ))d"; fi
    return
  fi
  (( m = (s + 59) / 60 ))
  if (( m < 60 )); then REPLY="${m}m"
  elif (( m < 600 )); then (( m % 60 )) && REPLY="$(( m / 60 ))h $(( m % 60 ))m" || REPLY="$(( m / 60 ))h"
  elif (( s < 86400 )); then REPLY="$(( s < 36000 ? 10 : s / 3600 ))h"
  elif (( s < 864000 )); then (( s % 86400 / 3600 )) && REPLY="$(( s / 86400 ))d $(( s % 86400 / 3600 ))h" || REPLY="$(( s / 86400 ))d"
  else REPLY="$(( s / 86400 ))d"; fi
}

# REPLY = "<used percentage> <resets at>" of window $2 in the saved text $1; 1 when it has none.
window_values() {
  emulate -L zsh
  local body=$1 name=$2 inner
  [[ $body =~ "\"$name\"[[:space:]]*:[[:space:]]*\\{([^{}]*)\\}" ]] || return 1
  inner=$match[1]
  [[ $inner =~ '"used_percentage"[[:space:]]*:[[:space:]]*(-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?)' ]] || return 1
  REPLY=$match[1]
  [[ $inner =~ '"resets_at"[[:space:]]*:[[:space:]]*([0-9]+)' ]] || return 1
  REPLY+=" $match[1]"
}

# REPLY = the face for the saved limits at time $1, as limits_frame arguments: "off <lang>" without a file (the status
# line was never turned on, or Claude Code has not answered since) or without a window in it.
face_at() {
  emulate -L zsh
  setopt extended_glob
  local -i now=$1 used resets
  local -a files cols
  local saved name tag age
  files=( $DESMAPTIC_STORAGE/ClaudeLimits/*.json(N.om[1]) )
  REPLY="off $lang"
  (( $#files )) || return 0
  IFS= read -r -d '' saved < $files[1]
  [[ $saved =~ '"updated":([0-9]+)' ]] || return 0
  span_text $(( now - match[1] )) down; age=$REPLY
  for name tag in five_hour 5h seven_day 7d; do
    window_values $saved $name || continue
    resets=${REPLY#* }
    if (( resets <= now )); then
      cols+=( $tag r - )
    else
      (( used = ${REPLY% *} + 0.5 ))
      (( used < 0 )) && used=0
      (( used > 100 )) && used=100
      span_text $(( resets - now )) up
      cols+=( $tag $used ${REPLY// /_} )
    fi
  done
  REPLY="off $lang"
  (( $#cols )) || return 0
  REPLY="$(( $#cols == 6 ? 2 : 1 )) $age $cols"
  REPLY=${${REPLY/#2/two}/#1/one}
}

if [[ $1 == --face ]]; then
  shift
  limits_frame "$@"
  exit 0
fi
# The hint's language: the setting above, else the first of the Mac's languages ("ru-RU" → ru).
if [[ -z $lang ]]; then
  langs=$(defaults read -g AppleLanguages 2>/dev/null)
  lang=${${(f)langs}[2]:-}
  lang=${${lang//[[:space:]\"(),]/}[1,2]}
fi
[[ $lang == (en|de|es|fr|ru) ]] || lang=en

if [[ $1 == --read ]]; then
  [[ $2 == <-> ]] || { print -u2 -- "usage: startup.zsh --read <unix seconds>"; exit 2 }
  face_at $2
  limits_frame ${=REPLY}
  exit 0
fi
[[ -n $DESMAPTIC_STORAGE ]] || { print -u2 -- "Claude limits: DESMAPTIC_STORAGE is not set"; exit 1 }

# MARK: - Loop

api="http://127.0.0.1:9848/api/update-button"

post() {   # $1 the frame → 0 when the agent took it
  local p=$1 code
  [[ -n $CLAUDE_LIMITS_DRY ]] && { print -r -- "frame: $p"; return 0 }
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  code=$(curl -q -s -m 5 -o /dev/null -w '%{http_code}' "$api" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"{{CELL_ID}}\",\"svg\":{\"source\":\"$p\",\"duration\":0.8}}")
  [[ $code == 200 ]]
}

shown=""
while true; do
  face_at $EPOCHSECONDS
  if [[ $REPLY != "$shown" ]]; then
    if post "$(limits_frame ${=REPLY})"; then
      shown=$REPLY
    else
      zselect -t 1000                           # the agent is busy or restarting: try again in 10 s
      continue
    fi
  fi
  zselect -t 1500
done
