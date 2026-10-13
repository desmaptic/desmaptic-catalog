#!/bin/zsh
# Visualizer, "Kolorofon" edition: the sound the Mac plays drawn as one picture across a page of 48 1x1 buttons
# (8 bands x 6 levels). An iPhone shows the page's first four levels (8 x 4, 32 keys), an iPad all six (8 x 6); the
# picture is drawn for the grid the phone shows (with the device in landscape bass is on the left, in portrait at
# the top). Effects Bars, Amoeba, Lava and Curve, nine colour themes, a calm idle look in silence that holds still
# after a while. Tap any key: a control column appears for 4 s — power, effect, theme; tap the effect or theme key to
# switch, power to turn the visualizer off (a calm dark deck; the next tap turns it on again).
#
# The levels come from the agent (GET /api/audio/levels): it listens to the Mac's output only while a widget asks,
# and this page asks only while it is on the phone's screen — the macOS "system audio recording" question comes up
# the first time the page is open, never before. Every key is a window onto one world (100 units per key, the key's
# own viewBox), and every frame of a key has the same elements in the same order in every effect, theme, state,
# orientation and grid, so the phone glides between frames instead of cross-fading.
#
# Processes: this zsh loop keeps the time, reads taps, watches the phone's screen and talks HTTP to the agent over
# ONE keep-alive connection (zsh/net/tcp; the token goes into the request by `print`, a builtin, never onto a
# command line; a frame's keys go out in one write, their answers read in order); one long-lived awk draws. Nothing
# is started per frame.
#
# The buttons' tap command writes "<button id> <time>" to $DESMAPTIC_STORAGE/gallery/visualizer/k-tap; effect, theme
# and power are kept in k-effect, k-theme and k-power next to it. Two taps within one look at that file (83 ms)
# count as one.
#
# The keys come from the phone: GET /api/view lists every button on screen with its place on the upright page and
# the Gallery entry it came from. This page's buttons are "visualizer.r<row>c<col>" (row = band, col = level); the
# loop draws only while its own button ({{CELL_ID}}) is among them — then its page is the one on the screen. A key the
# user moved is drawn where it stands now; a key the phone does not list (the iPad's two levels on an iPhone) is not.
#
# Tool modes (arguments; they never open a connection): --faces out.json (the Gallery's resting and sample faces),
# --cover out.svg (the Gallery card), --dump <4|6> <portrait|landscape> <HH:MM> <step> out.json (every key's frame
# after <step> tenths of a second of synthetic music; the visualizer keeps no clock, HH:MM is not used), --bars <4|6>
# <portrait|landscape> <h0,…,h7>[:<h0,…,h7>] out.json (every key's frame and glide of Bars standing at these heights
# in keys, bass to treble; after a colon, of the regular frame that moves them to the second heights; as --dump).
# Any other argument prints the usage and exits 2.
#
# Modes (environment, for trying it out; none of them opens a connection):
#   VIS_DRY=1            synthetic music in real time, frames drawn and counted, nothing posted
#   VIS_DUMP=<folder>    synthetic music on a virtual clock, as fast as it runs: every drawn frame of the 48 keys is
#                        written to the folder, then the budget. VIS_SECONDS, VIS_EFFECT, VIS_THEME, VIS_POWER,
#                        VIS_ORIENT=portrait, VIS_GRID=6 (the iPad's grid), VIS_MUSIC=0 (silence),
#                        VIS_EVENTS="t:tap:band:level,t:orient:portrait,t:grid:6,t:music:0,t:key,t:effect:N,…" (key:
#                        every key sent again, as the loop does every 30 s; effect: a switch straight to effect N)
#   VIS_REPLAY=<file>    with VIS_DRY or VIS_DUMP: recorded answers of the levels route instead of the synthetic music,
#                        lines "<unix time> <answer>", played at their recorded times (a pause over 1 s in the
#                        recording is closed), looped; the same parsing and shaping as the agent's answers
#   VIS_FACES=<file>     the 48 saved faces (the calm idle look) as JSON
#   VIS_STORAGE=<folder> where the dry modes keep k-* files (none without it)
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C                                 # numbers with a dot, ${#…} counts bytes (Content-Length)
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP                      # until the real handler below is defined
trap '' PIPE                                    # a connection the agent closed must not kill the loop
zmodload zsh/net/tcp zsh/system zsh/zselect zsh/datetime || { print -u2 -- "Visualizer: zsh modules net/tcp, system, zselect and datetime are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Visualizer: zsh module files is missing"; exit 1 }
typeset -F SECONDS

port=9848
client="{{CELL_ID}}"                            # the button that runs this script: its own levels client
[[ -z $client || $client == *[^[:alnum:]-]* ]] && client=visualizer
client_id=${(U)client}
token=${DESMAPTIC_TOKEN:-}

# MARK: - The page

# The page's 48 keys in scene order: ids[band * 6 + level + 1], band 0 = bass, level 0 = the bottom with the phone in
# landscape (on the page: portrait row = band, portrait column = level). Levels 4 and 5 are the page's iPad columns:
# an iPhone does not show them. The ids come from the phone's view (view_check); until then, and for a key the phone
# does not list, the id is "-" and the key is not drawn. A dry run gets placeholder ids.
page_cells() {
  integer i
  reply=()
  for (( i = 0; i < 48; i++ )); do
    if (( dry )); then reply+=("00000000-0000-0000-0000-0000000000${(l:2::0:)i}"); else reply+=(-); fi
  done
}

# set_keys <48 ids>: the page's keys as the phone shows them now. The renderer is told, and every key goes again. A key
# the phone no longer lists here (moved to another page, taken off the scene) is not drawn any more: it goes back to
# its own face at once, or it would keep the last frame until the phone reconnects. drawn_ids: every key listed on
# this run — the stop resets them all.
set_keys() {
  integer i
  local id
  local -a dropped
  for id in $page_ids; do [[ $id == - || " $1 " == *" $id "* ]] || dropped+=($id); done
  ids=$1 page_ids=(${=1})
  cell_index=()
  for (( i = 1; i <= 48; i++ )); do
    [[ $page_ids[i] == - ]] && continue
    cell_index[$page_ids[i]]=$(( i - 1 )) drawn_ids[$page_ids[i]]=1
  done
  aw_call "I $ids" && need_key=1
  for id in $dropped; do api POST /api/update-button "{\"cellId\":\"$id\",\"reset\":true}" 2 || break; done
}

# MARK: - The renderer (awk)

read -r -d '' RENDER <<'AWK'
# Commands on stdin, one per line. Every answer is a series of records, each a 10-digit byte count and that many
# bytes, ended by an empty record: the loop reads each record as its own string and never scans the whole answer.
#   I <id> x48      the page's buttons in scene order ("-": a key the phone does not list, not drawn)
#   T <now> <effect> <theme> <power> <column> <switched> <tapped> <behind> <portrait> <grid> <audible> <bass> <pulse> <beat> <l0> .. <l19> <fresh>
#                   one tick (grid: the levels the phone shows, 4 or 6; fresh: 1 when the levels were asked for since
#                   the last tick, 0 when they are the last answer again): answers "N <seconds to the next tick, 0 =
#                   none needed> <idle> <drew> <asleep>", then one update-button body per shown key whose frame changed
#   K               forget what the phone has: the next tick draws and carries every shown key
#   S <t>           a synthetic levels line (the agent's format) for the time t
#   P <file>        load recorded answers (lines "<unix time> <answer>") for R
#   R <t>           the recorded answer for the time t: per field the peak of the lines since the last R, as the agent
#                   holds peaks for a client; none since then: the last line fallen as the agent's bars fall
#   F <effect> <theme>   the 48 saved faces, one SVG per record
#   X               the Gallery's sample: 48 stills of a staged Bars frame, one SVG per record
#   B <grid> <portrait> <h0> .. <h7> [<g0> .. <g7>]   Bars standing at these heights (keys), then the regular
#                   frame that moves them to g: every key as "<glide> <frame>" ("-" for a key not drawn)
#   D <folder>      dump mode: every drawn frame is also written to the folder
#   V [c]           every key's picture now as a still ("-" for a key not drawn); c: gradients named per key
#   C               every key's frame now as it was drawn ("-" for a key not drawn)
#   Q               the dump summary
BEGIN {
  CONVFMT = "%.6g"; OFMT = "%.6g"
  NP = 16; PI = atan2(0, -1)
  H16 = "0123456789ABCDEF"
  for (i = 0; i < 256; i++) HX[i] = substr(H16, int(i / 16) + 1, 1) substr(H16, i % 16 + 1, 1)
  for (i = 0; i < NP; i++) { COSP[i] = cos(i / NP * 2 * PI); SINP[i] = sin(i / NP * 2 * PI) }
  # Themes: five ramp stops from bass (left) to treble (right), the night an unlit key is tinted from, the hot
  # core of glows and the colour of the theme's name. Every theme has the same stops everywhere they are used,
  # so a theme change is new numbers only: the phone glides from one palette to the next.
  NT = 0
  theme("SYNTHWAVE", "79ECFB 6CA2FA 7A82F9 D882F8 EE70F0", "0A1432", "FFF2FF", "F49CF6")
  theme("TOXIC", "E6FB78 BFFA6C 6FF95A 22F74A 10F2A2", "081A10", "F4FFE6", "A6FF6E")
  theme("ORCHID", "C6A4FA D69BF9 E88DF8 F97EF0 FF69B4", "170F34", "FFF0FB", "F2A2F4")
  theme("EMBER", "FFE07A FFB55A FF8748 FF5846 F2366E", "1C0A07", "FFF6DF", "FFB45A")
  theme("GLACIER", "EFFCFF B4ECFF 78CFFF 58A4FF 5E78FF", "061329", "FFFFFF", "9CDBFF")
  theme("AURORA", "8AFFC6 4EEFD6 4CC4FF 7A8BFF B67AFF", "061A21", "F0FFFA", "72F0D2")
  theme("SORBET", "FFD1A6 FFB2C8 E4B5FF B6C7FF A6EFE2", "1A1320", "FFFFFF", "FFC0D6")
  theme("PRISM", "FF5E6E FFB648 7EF06A 48D4FF A87CFF", "0F0F19", "FFFFFF", "FFD46A")
  theme("MONO", "FFFFFF E6E9F0 CFD3DD E6E9F0 FFFFFF", "0D0E12", "FFFFFF", "E4E6EC")
  split("BARS AMOEBA LAVA CURVE", w, " "); for (i = 0; i < 4; i++) ENAME[i] = w[i + 1]
  # Seconds between frames while music plays and in the idle look. The effects that repaint many keys at once
  # draw less often; a glide always covers the whole interval, so motion stays continuous. Amoeba and Curve ask for
  # the levels on every frame (Curve up to 15 a second: the script allows itself 16 level requests a second). Bars draw 22 frames a second and ask on
  # every second one: between two answers the bars move on towards the last one (BARW below). Lava asks every
  # LAVAPOLL between its frames (it listens for the beat). Idle ticks come every 0.25 s (to notice music), so the
  # idle intervals are whole multiples of it.
  ACTIV[0] = 1 / 22; ACTIV[1] = 1 / 9; ACTIV[2] = 1 / 6; ACTIV[3] = 1 / 15
  IDLEIV[0] = 0.5; IDLEIV[1] = 0.75; IDLEIV[2] = 1; IDLEIV[3] = 0.75
  # The grid: 8 bands x GRID levels (4 on an iPhone, 6 on an iPad). The world's y runs 0 (bottom) .. GRID up; in
  # SVG units every level keeps its place whatever the grid (y = (WT - world y) * 100), so a key's viewBox never
  # moves. WT = 4, as in the phone-only version: its 32 keys keep their viewBox (their saved faces stay valid), and
  # the iPad's levels 4 and 5 sit above them at negative y. NLV: the page's levels (keys are ids[band * NLV + level]).
  WT = 4; NLV = 6; NKEY = 48; GRID = 4; WASGRID = 4
  # Curve: each band's point follows the spectrum as a critically damped spring (CURVEW, 1/s), so the line's points
  # move with continuous velocity between the frames the phone glides through; CURVEQ: steps per key its points
  # are drawn in. Every key the line passes near changes on every frame (the pieces must join), so Curve draws up
  # to 11 frames a second but at most about CURVEBUDGET key frames a second: when the line spreads over many keys the
  # frames come further apart. CURVECHG, the keys a frame changes, jumps up at once and comes down slowly, so a
  # loud start never bursts over the budget; a frame always comes at the interval promised with the one before. The
  # budget is what an old iPad keeps up with in loud music, on either grid.
  # CURVEV: the fastest a point moves, in the line's full height per second (the height is GRID - 0.7 keys): a line
  # that crosses keys faster than they can be kept in step breaks up on the phone. Each frame's move is at most what
  # the frame before promised (CMOVE, at most CMOVEMAX keys), and every key the line may reach before the next frame
  # already holds the real line (CREAL, in curve()): a key never glides in from the flat piece outside its window.
  # Bars are paced the same way by BARCHG against UPDBUDGET, the keys a Bars frame changes on average (it rises 20 %
  # and falls 10 % of the way a frame: a louder moment slows the frames down sooner than a quieter one speeds them
  # up). UPDBUDGET, too, is what an old iPad keeps up with in loud music.
  CURVEW = 10; KWE = 0.2; CURVEQ = 50; CURVEBUDGET = 500; CURVECHG = 0; LASTIV = 0; BARCHG = 0; CURVEV = 1 / 0.7; CMOVE = 0.1; CMOVEMAX = 0.9
  UPDBUDGET = 215
  # Glide lengths that are not "the interval and a bit": an effect, theme or power switch; the fade of a curve
  # into blobs or back (the new kind appears once it is done); turning the phone; a bar key that must become
  # completely full or empty; the attack of a beat flash. The idle look holds still after SLEEPAFTER seconds.
  # SHOWDUR: Curve's new line fades in as it did at 5 frames a second (0.2 s x 1.2), not over one of its short frames.
  SWDUR = 0.45; XFADE = 0.25; XF = XFADE; ORIENTDUR = 0.3; SNAPDUR = 0.04; ATTACK = 0.07; SLEEPAFTER = 12; SHOWDUR = 0.24; GLIDEPAD = 0.02
  # Bars: each band's height follows its shaped level (below) as a critically damped spring, faster up (BARWUP, 1/s:
  # a beat covers 80 % of its rise within about 0.07 s) than down (BARWDN: the bar falls, it does not drop), so the
  # 22 frames between the 11 answers a second move on smoothly; heights are drawn in BARQ steps per key (fine
  # steps: a bar coming to rest does not stop with a jerk). The keys under a bar's top are whole; the key holding
  # the top is lit as far up as the bar reaches (render: TOPK, FILL). The top glows white-hot, and the key under it
  # keeps that glow until the top holds BARHYS of its key, getting it back only once the top falls into it: a bar
  # standing at a key's edge does not flicker there.
  BARWUP = 60; BARWDN = 16; BARQ = 20; BARHYS = 0.15
  # A lit key's glow (GLOWT / GLOWB, setTheme): the bar's top white-hot (BTOP) in its band's colour; under it the
  # band's colour whitened by GLOWHOT in the middle and deepened toward the night by GLOWDEEP x the share of the
  # six levels above the key (the louder the bar, the brighter its body); every glow deepened again by GLOWEDGE at
  # the rim, GLOWR from the centre. The glow belongs to the lit part (objectBoundingBox): round about the centre of a
  # whole key, so the key reads the same either way up (the Gallery shows the page turned, a screenshot upright);
  # squeezed into a top lit part-way, its white centre in the middle of it. A key's glow depends on the key and on
  # whether it is the top, never on the bar's height: a bar that grows or falls changes only the keys at its top.
  # LTMIN: the lit part of a dark key (keys), there and invisible — an empty box leaves the glow nothing to map onto.
  GLOWHOT = 0.18; GLOWDEEP = 0.45; GLOWEDGE = 0.35; GLOWR = 0.72; LTMIN = 0.001
  # Level shaping, one step every effect draws from (Bars heights, Amoeba and Lava sizes, Curve heights). The agent
  # already scales every band against its own recent peak, so in music its bands sit near the top most of the time
  # (recorded real music: medians up to 0.88, the 90th percentiles 0.83-0.97, bars completely full up to 9 % of the
  # time). Per band (and for the bass), H follows the AGQ-th percentile of the recent level: it rises AGUP a second
  # while the level is above it and falls AGDOWN a second while it is under (AGUP = AGDOWN x AGQ / (1 - AGQ), so it
  # settles where 10 % of the levels are above it; a single loud moment moves it by about 2 %: no pumping).
  # A level at H is drawn at AGAT of the height; under H the height falls as (level / H) ^ AGGAMMA, so the
  # differences between loud moments stay visible; above H it climbs to the top within AGHEAD (a curve with no kink
  # at H), so only the loudest few per cent reach the top (2-5 % of the time per band in the recording; a Bars bar,
  # smoothed, is completely full 0.1-1.5 %). H never goes under AGFLOOR nor, for the 8 bands, under
  # AGKAPPA of the loudest band's H (a band with almost nothing in it stays low). A band under AGINFO says nothing
  # about the band's loudness and does not move H. A start, and music after AGQUIET seconds of silence (or of every
  # band under AGINFO; also no answer for that long), puts H back at AGRESET, the top of the scale, where it stays for
  # AGHOLD seconds (it may rise, not fall): the first second of a track is never a blast to the top; for AGWARM
  # seconds after that H may fall up to 1 + AGWARMK times faster, so a new track fills the height within about 4-5 s.
  AGQ = 0.9; AGDOWN = 0.03; AGUP = AGDOWN * AGQ / (1 - AGQ); AGAT = 0.78; AGGAMMA = 1.8; AGHEAD = 0.015
  AGFLOOR = 0.35; AGKAPPA = 0.6; AGINFO = 0.02; AGQUIET = 1; AGRESET = 1; AGHOLD = 1; AGWARM = 4; AGWARMK = 3
  AGC2 = (1 - AGAT - AGAT * AGGAMMA * AGHEAD) / (AGHEAD * AGHEAD)
  for (b = 0; b <= 8; b++) AGH[b] = AGRESET
  AGSTART = 1; AGWARMAT = -100; AGLAST = -100; AGSILENT = 0; BARON = 0; BARAT = -100
  # The agent's 20 log bands (35 Hz - 14 kHz) onto 8: each key band is exactly 2.5 agent bands wide, weighted by
  # how much of each agent band it covers.
  for (b = 0; b < 8; b++) {
    lo = 2.5 * b; hi = lo + 2.5
    MAPFROM[b] = int(lo); MAPTO[b] = int(hi - 0.001)
    for (k = MAPFROM[b]; k <= MAPTO[b]; k++) { a = k > lo ? k : lo; z = k + 1 < hi ? k + 1 : hi; MAPW[b, k] = z - a }
  }
  # Approximate advance of the system font's bold capitals, in em: the names are sized to fit the key.
  split("A .72 B .68 C .71 D .73 E .61 F .59 G .75 H .75 I .29 J .55 K .69 L .57 M .89 N .75 O .77 P .65 Q .77 R .68 S .64 T .62 U .73 V .70 W .99 X .69 Y .67 Z .64", w, " ")
  for (i = 1; i < 52; i += 2) CAPW[w[i]] = w[i + 1] + 0
  CAPW[" "] = 0.26
  # A slot while nothing uses it: constant strings, so a parked slot never makes a frame differ.
  PPATH = "M0 0"; for (i = 0; i < NP; i++) PPATH = PPATH "C0 0 0 0 0 0"; PPATH = PPATH "Z"
  PSTOP = "<stop offset='0' stop-color='#000000' stop-opacity='0'/>"
  for (k = 0; k < 4; k++) {
    PRAD[k] = "<radialGradient id='f" k "' gradientUnits='userSpaceOnUse' cx='0' cy='0' r='0'>" PSTOP PSTOP PSTOP PSTOP "</radialGradient>"
    PTAGP[k] = stagp(k, PPATH, 0, "#000000", 0, 0)
  }
  # Curve: two strokes of one line (slots 2 and 3): a soft glow and the thin whitened core. Slots 0 and 1 stay
  # transparent: at most two wide strokes on a key the line crosses, and a stroke that must not show is transparent,
  # not hidden outside the key's window. CWID[0] is only the reach: the widest stroke that shows.
  split("26 26 26 7", w, " "); for (k = 0; k < 4; k++) CWID[k] = w[k + 1] + 0
  split("0 0 0.34 1", w, " "); for (k = 0; k < 4; k++) CREST[k] = w[k + 1] + 0
  split("0 0 0.16 0", w, " "); for (k = 0; k < 4; k++) CFLASH[k] = w[k + 1] + 0
  split("0 0 0.25 0.72", w, " "); for (k = 0; k < 4; k++) CWHITE[k] = w[k + 1] + 0
  MH[0] = 24; MH[1] = 40; MH[2] = 30                      # the logo mark's three bars
  # Lava: four blobs, each at home in its own part of the deck (y for the phone's grid; setGrid scales it).
  split("1.45 3.15 4.85 6.55", w, " ")
  for (k = 0; k < 4; k++) { HOME[k] = w[k + 1] + 0; LX[k] = HOME[k]; LY[k] = 2 + (k % 2 == 0 ? -0.7 : 0.7); LVX[k] = 0; LVY[k] = 0; LR[k] = 0.6; LFL[k] = 0 }
  GS = 1; LRS = 1; AMS = 1; AMY = 1.12; AMW = 14; AMIV6 = 1 / 7
  # Lava with music: each blob's size follows its band (and the bass) through the shaped levels — up within
  # LAVAUP seconds, down over LAVADOWN — between LAVAMIN and LAVAMIN + LAVARANGE; the louder, the hotter its core. A
  # beat makes every blob flash (the core white-hot, the body brighter, the blob LAVASWELL larger, fading over
  # LAVAFLASH seconds) and shoves it outwards (LAVAKICK). The levels are asked for every LAVAPOLL seconds while Lava
  # plays, so a beat is heard within about 0.1 s, and a beat is drawn at once (at least LAVABEATGAP after the frame
  # before, gliding like every other frame); the frames between come up to 6 a second, paced to about
  # LAVABUDGET key frames a second (an iPad's 48 keys: about 4).
  LAVAMIN = 0.4; LAVARANGE = 0.95; LAVAUP = 0.25; LAVADOWN = 0.35; LAVAFLASH = 0.3; LAVASWELL = 0.05; LAVAKICK = 1.5
  LAVAPOLL = 1 / 11; LAVABEATGAP = 0.12; LAVAATTACK = 0.09; LAVABUDGET = 140; LAVACHG = 0
  # Synthetic music (dry and dump modes): 120 BPM, 50 s of intro, full, breakdown, quiet, silence and drop.
  split("55 43.65 65.41 49", w, " "); for (i = 0; i < 4; i++) ROOT[i] = w[i + 1] + 0
  split("440 523.25 587.33 659.25 783.99 880 1046.5 1174.66 1318.51 1567.98", w, " "); for (i = 0; i < 10; i++) SCALE[i] = w[i + 1] + 0
  split("2093 2637.02 3135.96 4186.01", w, " "); for (i = 0; i < 4; i++) ARP[i] = w[i + 1] + 0
  LOGR = log(14000 / 35) / 20
  SSTEP = 0.01; STIME = -SSTEP; SLOUD = -100; SBEATAT = -100; SLASTBEAT = -1; SEED = 12345; SBASSL = 0; SBASSPK = 0
  for (k = 0; k < 20; k++) { SLV[k] = 0; SPK[k] = 0 }
  # State
  THEME = -1; LASTNOW = -1; LASTDRAW = -100; LASTEFFECT = -1; LASTCLASS = 0; SILENT = 10; WASIDLE = 0; WASCOL = 0
  WASPORT = 0; FORCE = 1; KINDHOLD = -1; TRANSUNTIL = -1; SHOWUNTIL = -1; HOLDUNTIL = -1; IDLESINCE = 0; IDLEPREV = 0; SLEEPING = 0; PENDBEAT = 0
  BEATENV = 0; CLOCK = 0; DCLOCK = 0; IVNOM = 0; IVAVG = 0.1; DUMP = ""; FRAMENO = 0; NSEG = 0
  for (i = 0; i < NKEY; i++) { PF[i] = -1; ID[i] = "cell" i }
  FLAT24 = ""; for (i = 0; i < 24; i++) FLAT24 = FLAT24 " 0"; RPN = 0
  for (b = 0; b < 8; b++) LV[b] = 0
  for (k = 0; k < 4; k++) { DLX[k] = LX[k]; DLY[k] = LY[k]; DLVX[k] = 0; DLVY[k] = 0; DLR[k] = LR[k]; DLFL[k] = 0 }
}

function out(s) { printf "%010d%s", length(s), s }
function done() { printf "%010d", 0; fflush() }
function clamp(v, a, b) { return v < a ? a : v > b ? b : v }
function absf(v) { return v < 0 ? -v : v }
# One decimal, no trailing ".0" (numbers print through CONVFMT).
function n1(v) { return v >= 0 ? int(v * 10 + 0.5) / 10 : -int(-v * 10 + 0.5) / 10 }
function n2(v) { v = clamp(v, -1000, 1000); return v >= 0 ? int(v * 100 + 0.5) / 100 : -int(-v * 100 + 0.5) / 100 }
function hexv(s) { return (index(H16, substr(s, 1, 1)) - 1) * 16 + index(H16, substr(s, 2, 1)) - 1 }
function byte(v) { v = int(v + 0.5); return v < 0 ? 0 : v > 255 ? 255 : v }
function hex(r, g, b) { return "#" HX[byte(r)] HX[byte(g)] HX[byte(b)] }
function mix(r, g, b, r2, g2, b2, t) { t = clamp(t, 0, 1); CR = r + (r2 - r) * t; CG = g + (g2 - g) * t; CB = b + (b2 - b) * t }
function theme(name, ramp, night, hot, label,    p, i) {
  TNAME[NT] = name
  split(ramp, p, " ")
  for (i = 0; i < 5; i++) { TR[NT, i] = hexv(substr(p[i + 1], 1, 2)); TG[NT, i] = hexv(substr(p[i + 1], 3, 2)); TB[NT, i] = hexv(substr(p[i + 1], 5, 2)) }
  TNR[NT] = hexv(substr(night, 1, 2)); TNG[NT] = hexv(substr(night, 3, 2)); TNB[NT] = hexv(substr(night, 5, 2))
  THR[NT] = hexv(substr(hot, 1, 2)); THG[NT] = hexv(substr(hot, 3, 2)); THB[NT] = hexv(substr(hot, 5, 2))
  TLABEL[NT] = "#" label
  NT++
}
# The theme's ramp at t (0 = bass, 1 = treble) into CR CG CB.
function ramp(t,    x, i) {
  x = clamp(t, 0, 1) * 4; i = int(x); if (i > 3) i = 3; x -= i
  CR = TR[THEME, i] + (TR[THEME, i + 1] - TR[THEME, i]) * x
  CG = TG[THEME, i] + (TG[THEME, i + 1] - TG[THEME, i]) * x
  CB = TB[THEME, i] + (TB[THEME, i + 1] - TB[THEME, i]) * x
}
# Everything a theme decides, once per theme change.
function setTheme(t,    b, k, r, g, bl, nr, ng, nb, lv, rim, hot) {
  THEME = t
  nr = TNR[t]; ng = TNG[t]; nb = TNB[t]
  HOTR = THR[t]; HOTG = THG[t]; HOTB = THB[t]
  for (b = 0; b < 8; b++) {
    ramp(b / 7); r = CR; g = CG; bl = CB
    BCOL[b] = hex(r, g, bl); BCR[b] = r; BCG[b] = g; BCB[b] = bl
    mix(r, g, bl, 255, 255, 255, 0.6); BTOP[b] = hex(CR, CG, CB)
    mix(nr, ng, nb, 0, 0, 0, 0.3); mix(CR, CG, CB, r, g, bl, 0.09); BASEBARS[b] = hex(CR, CG, CB)
    mix(nr, ng, nb, 0, 0, 0, 0.45); mix(CR, CG, CB, r, g, bl, 0.04); BASEOTHER[b] = hex(CR, CG, CB)
    for (k = 0; k < 4; k++) { mix(r, g, bl, 255, 255, 255, CWHITE[k]); BSTROKE[b, k] = hex(CR, CG, CB) }
    # The glow's stops: GLOWT on the bar's top key, GLOWB[b, level] under it.
    mix(r, g, bl, nr, ng, nb, GLOWEDGE); GLOWT[b] = glowStop(0, BTOP[b]) glowStop(0.55, BCOL[b]) glowStop(1, hex(CR, CG, CB))
    mix(r, g, bl, 255, 255, 255, GLOWHOT); hot = glowStop(0, hex(CR, CG, CB))
    for (lv = 0; lv < NLV; lv++) {
      mix(r, g, bl, nr, ng, nb, GLOWDEEP * (NLV - 1 - lv) / NLV); rim = glowStop(0.55, hex(CR, CG, CB))
      mix(CR, CG, CB, nr, ng, nb, GLOWEDGE); GLOWB[b, lv] = hot rim glowStop(1, hex(CR, CG, CB))
    }
  }
  mix(nr, ng, nb, 0, 0, 0, 0.45); BASEOFF = hex(CR, CG, CB)
  for (k = 0; k < 3; k++) { ramp(0.15 + 0.35 * k); MARK[k] = hex(CR, CG, CB) }
}
function glowStop(o, c) { return "<stop offset='" o "' stop-color='" c "'/>" }
# The effect's kind of slot: 0 none (off, Bars), 1 blobs (Amoeba, Lava), 2 a curve.
function kindOf(e, p) { return !p || e == 0 ? 0 : e == 3 ? 2 : 1 }

# MARK: SVG pieces (x 0..8 to the right and y 0..GRID up in keys; 100 units per key, y down from WT)

function pt(x, y) { return n1(x * 100) " " n1((WT - y) * 100) }
# Closed Catmull-Rom loop through n points: one cubic per point, so the commands never change.
function loopPath(px, py, n,    d, i, a, b, c, e) {
  d = "M" pt(px[0], py[0])
  for (i = 0; i < n; i++) {
    a = (i + n - 1) % n; b = (i + 1) % n; c = (i + 2) % n
    d = d "C" pt(px[i] + (px[b] - px[a]) / 6, py[i] + (py[b] - py[a]) / 6) " " pt(px[b] - (px[c] - px[i]) / 6, py[b] - (py[c] - py[i]) / 6) " " pt(px[b], py[b])
  }
  return d "Z"
}
# An open curve through n points drawn forward and back over itself, closed: the same 16 cubics as a 16-point
# loop. collect: sample it for touches(), 8 steps a cubic (the polyline stays within 0.03 key of the curve). Every
# point is written once and used for both directions.
function curvePath(px, py, n, collect,    d, i, a, c, c1x, c1y, c2x, c2y, s, t, u, back) {
  FP[0] = pt(px[0], py[0]); d = "M" FP[0]; back = ""
  for (i = 0; i < n - 1; i++) {
    a = i > 0 ? i - 1 : 0; c = i + 2 < n ? i + 2 : n - 1
    c1x = px[i] + (px[i + 1] - px[a]) / 6; c1y = py[i] + (py[i + 1] - py[a]) / 6
    c2x = px[i + 1] - (px[c] - px[i]) / 6; c2y = py[i + 1] - (py[c] - py[i]) / 6
    if (collect) for (s = i > 0 ? 1 : 0; s <= 8; s++) {
      t = s / 8; u = 1 - t
      CSX[CSN] = u * u * u * px[i] + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * px[i + 1]
      CSY[CSN] = u * u * u * py[i] + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * py[i + 1]
      CSN++
    }
    FQ1[i] = pt(c1x, c1y); FQ2[i] = pt(c2x, c2y); FP[i + 1] = pt(px[i + 1], py[i + 1])
    d = d "C" FQ1[i] " " FQ2[i] " " FP[i + 1]
    back = "C" FQ2[i] " " FQ1[i] " " FP[i] back
  }
  s = FP[n - 1]; d = d "C" s " " s " " s back
  s = FP[0]
  return d "C" s " " s " " s "Z"
}
function stop(i, o, r, g, b, a) { STO[i] = o; STC[i] = hex(r, g, b); STA[i] = a }
function radial(id, cx, cy, r,    s, i) {
  s = "<radialGradient id='" id "' gradientUnits='userSpaceOnUse' cx='" n1(cx * 100) "' cy='" n1((WT - cy) * 100) "' r='" n1(r * 100) "'>"
  for (i = 0; i < 4; i++) s = s "<stop offset='" n2(STO[i]) "' stop-color='" STC[i] "' stop-opacity='" n2(STA[i]) "'/>"
  return s "</radialGradient>"
}
# A slot's element up to its opacity, which the key decides (0 while it appears or leaves, 1 when shown).
function stagp(k, d, fo, stroke, sw, so) {
  return "<path id='s" k "' d='" d "' fill='url(#f" k ")' fill-opacity='" n2(fo) "' stroke='" stroke "' stroke-width='" n1(sw) "' stroke-opacity='" n2(so) "' stroke-linecap='round' stroke-linejoin='round' opacity='"
}
function put(k, g, p, op) { PDEFS = PDEFS g; PTAGS = PTAGS p op "'/>" }
function bbox(px, py, n, pad,    i) {
  BX0 = 1e9; BY0 = 1e9; BX1 = -1e9; BY1 = -1e9
  for (i = 0; i < n; i++) { if (px[i] < BX0) BX0 = px[i]; if (px[i] > BX1) BX1 = px[i]; if (py[i] < BY0) BY0 = py[i]; if (py[i] > BY1) BY1 = py[i] }
  BX0 -= pad; BY0 -= pad; BX1 += pad; BY1 += pad
}

# MARK: Glow slots: four per frame, the same four elements in every effect

# A slot with its box; circle(k, x, y, r) narrows which keys it lights to those the round glow really reaches.
function setSlot(k, d, g, fo, sw, so, stroke, x0, y0, x1, y1) {
  SL[k] = 1; SLD[k] = d; SLG[k] = g; SLFO[k] = fo; SLSW[k] = sw; SLSO[k] = so; SLST[k] = stroke
  SLX0[k] = x0; SLY0[k] = y0; SLX1[k] = x1; SLY1[k] = y1; SLCURVE[k] = 0; SLCR[k] = 0
}
function circle(k, x, y, r) { SLCX[k] = x; SLCY[k] = y; SLCR[k] = r }
function computeSlots(   k) {
  for (k = 0; k < 4; k++) SL[k] = 0
  if (!POWER || EFFECT == 0) return
  if (EFFECT == 1) amoeba(); else if (EFFECT == 2) lava(); else curve()
}
# Whether slot k lights the key whose lower left corner is (x0, y0).
function touches(k, x0, y0, reach,    i, dx, dy, ax, bx, ay, by, lo, hi, ya, yb) {
  if (!(SLX1[k] > x0 && SLX0[k] < x0 + 1 && SLY1[k] > y0 && SLY0[k] < y0 + 1)) return 0
  if (SLCURVE[k]) {
    # The sampled line, piece by piece (left to right): its height where it crosses the key's reach, against it.
    # Across, the glow's reach (the line's points never move sideways); up and down, the reach asked for.
    ax = x0 - CREACH; bx = x0 + 1 + CREACH; ay = y0 - reach; by = y0 + 1 + reach
    for (i = CSLO[x0]; i < CSHI[x0]; i++) {
      lo = CSX[i] > ax ? CSX[i] : ax; hi = CSX[i + 1] < bx ? CSX[i + 1] : bx
      if (lo > hi) continue
      dx = CSX[i + 1] - CSX[i]; dy = CSY[i + 1] - CSY[i]
      ya = dx > 0 ? CSY[i] + (lo - CSX[i]) * dy / dx : CSY[i]
      yb = dx > 0 ? CSY[i] + (hi - CSX[i]) * dy / dx : CSY[i + 1]
      if ((ya < yb ? ya : yb) < by && (ya > yb ? ya : yb) > ay) return 1
    }
    return 0
  }
  if (SLCR[k] <= 0) return 1
  dx = SLCX[k] < x0 ? x0 - SLCX[k] : SLCX[k] > x0 + 1 ? SLCX[k] - x0 - 1 : 0
  dy = SLCY[k] < y0 ? y0 - SLCY[k] : SLCY[k] > y0 + 1 ? SLCY[k] - y0 - 1 : 0
  return dx * dx + dy * dy < SLCR[k] * SLCR[k]
}
# One soft shape in the middle of the deck: a white-hot core, a saturated body with a thin bright rim, a glow band
# hugging the rim and a round halo gone within a key. It breathes with the loudness, bulges with the spectrum
# (bass to one side, treble to the other) and pulses on every beat.
# The shape follows the music through critically damped springs (AMW, 1/s): the loudness, the bass and every band,
# so its size and bulges move with continuous speed between frames instead of jumping to each new poll.
function amSpring(key, target, dt, fresh,    x, v, e) {
  if (fresh || dt <= 0) { if (fresh) { AMF[key] = target; AMV[key] = 0 }; return AMF[key] }
  x = AMF[key] - target; v = AMV[key]; e = exp(-AMW * dt)
  AMF[key] = target + (x + (v + AMW * x) * dt) * e
  AMV[key] = (v - AMW * (v + AMW * x) * dt) * e
  return AMF[key]
}
function amoeba(   cx, cy, br, bg, bb, gr, gg, gb, rr, rg, rb, radius, pace, k, t, low, m, lvl, wob, r, dist, reach, near, outline, pulse, hr, hg, ccx, ccy, so, dt, fresh, en, bs, b) {
  cx = 4; cy = GRID / 2
  dt = NOW - AMAT; if (dt > 0.4) dt = 0.4
  fresh = !AMON || AMRENDER != RENDERS - 1
  if (SLEEPING && AMON) dt = 0
  en = amSpring("e", ENERGY, dt, fresh); bs = amSpring("b", BASS, dt, fresh)
  for (b = 0; b < 8; b++) AML[b] = amSpring(b, LV[b], dt, fresh)
  AMON = 1; AMAT = NOW; AMRENDER = RENDERS
  ramp(0.55); br = CR; bg = CG; bb = CB
  ramp(0.42); gr = CR; gg = CG; gb = CB
  ramp(0.22); mix(CR, CG, CB, 255, 255, 255, 0.35); rr = CR; rg = CG; rb = CB
  radius = AMS * (IDLE ? 0.6 + 0.04 * sin(CLOCK * 0.9) : 0.5 + 0.5 * en + 0.28 * bs + 0.12 * BEATENV)
  pace = IDLE ? 0.5 : 1
  reach = 0; near = 100
  for (k = 0; k < NP; k++) {
    t = absf(1 - 2 * k / NP) * 7
    low = int(t); if (low > 6) low = 6; m = t - low
    lvl = AML[low] * (1 - m) + AML[low + 1] * m
    wob = (IDLE ? 0.5 : 1) * (0.06 * sin(CLOCK * 1.3 * pace + k * 1.9) + 0.045 * sin(CLOCK * 0.77 * pace - k * 2.6))
    r = radius * (1 + (IDLE ? 0 : 0.6 * (lvl - en)) + wob)
    AX[k] = cx + COSP[k] * r; AY[k] = cy + SINP[k] * r * AMY
    dist = sqrt((AX[k] - cx) * (AX[k] - cx) + (AY[k] - cy) * (AY[k] - cy))
    if (dist > reach) reach = dist
    if (dist < near) near = dist
  }
  outline = loopPath(AX, AY, NP)
  pulse = IDLE ? 0 : BEATENV
  # The halo and the core are round glows that fade out before the edge of their own (larger) outlines.
  hr = near * 1.85
  hg = (IDLE ? 0.7 : 0.75) * (1 + 0.45 * pulse); if (hg > 1) hg = 1
  for (k = 0; k < NP; k++) { OX[k] = cx + (AX[k] - cx) * 1.95; OY[k] = cy + (AY[k] - cy) * 1.95 }
  stop(0, 0, gr, gg, gb, 0.44 * hg); stop(1, 0.55, gr, gg, gb, 0.36 * hg); stop(2, 0.78, gr, gg, gb, 0.13 * hg); stop(3, 1, gr, gg, gb, 0)
  setSlot(0, loopPath(OX, OY, NP), radial("f0", cx, cy, hr), 1, 0, 0, "#000000", cx - hr, cy - hr, cx + hr, cy + hr)
  circle(0, cx, cy, hr)
  # A glow band that hugs the rim: half of it lies under the body.
  bbox(AX, AY, NP, 0.17)
  so = 0.26 + 0.2 * pulse; if (so > 0.5) so = 0.5
  mix(gr, gg, gb, rr, rg, rb, 0.3)
  setSlot(1, outline, PRAD[1], 0, 28, so, hex(CR, CG, CB), BX0, BY0, BX1, BY1)
  circle(1, cx, cy, reach + 0.17)
  stop(0, 0, HOTR, HOTG, HOTB, 1)
  mix(br, bg, bb, HOTR, HOTG, HOTB, 0.5); stop(1, 0.32, CR, CG, CB, 1)
  stop(2, 0.74, br, bg, bb, 1)
  mix(br, bg, bb, 0, 0, 0, 0.08); stop(3, 1, CR, CG, CB, 1)
  bbox(AX, AY, NP, 0.04)
  setSlot(2, outline, radial("f2", cx, cy, reach), 1, 3.5, 1, hex(rr, rg, rb), BX0, BY0, BX1, BY1)
  circle(2, cx, cy, reach + 0.04)
  ccx = cx - 0.06 * radius; ccy = cy + 0.08 * radius
  for (k = 0; k < NP; k++) { OX[k] = ccx + (AX[k] - cx) * 0.72; OY[k] = ccy + (AY[k] - cy) * 0.72 }
  stop(0, 0, HOTR, HOTG, HOTB, 0.92); stop(1, 0.42, HOTR, HOTG, HOTB, 0.5); stop(2, 0.76, HOTR, HOTG, HOTB, 0.12); stop(3, 1, HOTR, HOTG, HOTB, 0)
  r = near * 0.55
  setSlot(3, loopPath(OX, OY, NP), radial("f3", ccx, ccy, r), 1, 0, 0, "#000000", ccx - r, ccy - r, ccx + r, ccy + r)
  circle(3, ccx, ccy, r)
}
# Glowing blobs that drift like a lava lamp; they swell with their band, and every beat makes them flash and shoves
# them outwards before a soft spring brings them back.
function lava(   k, i, r, wob, cr, cg, cb, lit, e, fl) {
  for (k = 0; k < 4; k++) {
    e = clamp((LR[k] - LAVAMIN) / LAVARANGE, 0, 1); fl = LFL[k]
    r = LR[k] * LRS * (1 + LAVASWELL * fl)
    for (i = 0; i < NP; i++) {
      # The outline stays outside the glow's radius: the blob's edge is always the gradient's soft fade.
      wob = 1.33 + 0.06 * sin(3 * i / NP * 2 * PI + CLOCK * 0.9 + k) + 0.05 * sin(2 * i / NP * 2 * PI - CLOCK * 0.6 + 2 * k)
      AX[i] = LX[k] + COSP[i] * r * wob; AY[i] = LY[k] + SINP[i] * r * wob
    }
    ramp(0.12 + 0.25 * k); cr = CR; cg = CG; cb = CB
    # The core: hotter the louder the blob's band, white-hot on a beat; the body brighter too.
    mix(cr, cg, cb, HOTR, HOTG, HOTB, 0.45 + 0.2 * e + 0.35 * fl)
    stop(0, 0, CR, CG, CB, 1); stop(1, 0.36 + 0.08 * fl, cr, cg, cb, 0.97); stop(2, 0.68, cr, cg, cb, 0.4 + 0.15 * e + 0.25 * fl); stop(3, 1, cr, cg, cb, 0)
    # The keys it can light are those the glow's radius reaches, not the outline's.
    lit = r * 1.2 + 0.05
    setSlot(k, loopPath(AX, AY, NP), radial("f" k, LX[k], LY[k], r * 1.2), 1, 0, 0, "#000000", LX[k] - lit, LY[k] - lit, LX[k] + lit, LY[k] + lit)
    circle(k, LX[k], LY[k], lit)
  }
}
function lavaStep(dt,    steps, h, s, k, t, speed, hx, hy, band, target, f) {
  steps = int(dt / 0.05) + 1; h = dt / steps
  speed = IDLE ? 0.55 : 1
  for (s = 1; s <= steps; s++) {
    t = CLOCK - dt + s * h
    for (k = 0; k < 4; k++) {
      hx = HOME[k] + 0.55 * sin(t * 0.11 * speed + k * 1.7)
      hy = GRID / 2 + 1.05 * GS * sin(t * (0.23 + 0.04 * k) * speed + k * 2.1)
      LVX[k] += ((hx - LX[k]) * 2.4 - LVX[k] * 2.1) * h
      LVY[k] += ((hy - LY[k]) * 2.4 - LVY[k] * 2.1) * h
      LX[k] = clamp(LX[k] + LVX[k] * h, 0.35, 7.65); LY[k] = clamp(LY[k] + LVY[k] * h, 0.35, GRID - 0.35)
      band = k * 2 + 1
      target = IDLE ? 0.72 : LAVAMIN + LAVARANGE * (0.7 * LV[band] + 0.3 * BASS)
      f = h / (target > LR[k] ? LAVAUP : LAVADOWN); if (f > 1) f = 1
      LR[k] += (target - LR[k]) * f
      LFL[k] *= exp(-h / LAVAFLASH)
    }
  }
}
function lavaKick(   k, dx, dy, l) {
  for (k = 0; k < 4; k++) {
    dx = LX[k] - 4; dy = LY[k] - GRID / 2
    l = sqrt(dx * dx + dy * dy); if (l < 0.3) l = 0.3
    LVX[k] += dx / l * LAVAKICK; LVY[k] += dy / l * LAVAKICK * 0.47 * GS
  }
}
# A beat's flash, after the tick's step (the frame drawn on the beat shows it whole): the louder the blob's band, the
# brighter.
function lavaFlash(   k, fl) {
  for (k = 0; k < 4; k++) { fl = 0.55 + 0.45 * LV[k * 2 + 1]; if (fl > LFL[k]) LFL[k] = fl }
}
# The spectrum as one glowing line on a black deck. Only the keys the line passes near light up.
# Each band's point follows its level as a critically damped spring (CURVEW): no overshoot, and the velocity carries
# over from frame to frame, so the straight glides the phone draws between frames join without sharp turns; no
# faster than CURVEV. When the line starts (a switch into Curve, a start, the other grid) the points start where the
# levels are; while it is shown it never jumps (after idle or a pause it moves on from where it is, within the
# limit); asleep, the line holds (the 30-s keyframe then carries exactly what the phone has).
function curve(   b, y, d, k, x, e, v, dt, hold, was, lim, fresh) {
  dt = NOW - CFAT; if (dt > 0.4) dt = 0.4
  hold = SLEEPING && CFON; lim = CMOVE; fresh = !CFON || CFRENDER != RENDERS - 1
  for (b = 0; b < 8; b++) {
    CPX[b] = 0.12 + b * (8 - 0.24) / 7
    if (!hold) {
      y = IDLE ? 0.5 + 0.14 * sin(CLOCK * 0.8 + b * 0.8) : 0.3 + LV[b] * (GRID - 0.7)
      if (fresh || CURVEW <= 0) { CFY[b] = y; CFV[b] = 0 }
      else if (dt > 0) {
        x = CFY[b] - y; v = CFV[b]; e = exp(-CURVEW * dt); was = CFY[b]
        CFY[b] = y + (x + (v + CURVEW * x) * dt) * e
        CFV[b] = (v - CURVEW * (v + CURVEW * x) * dt) * e
        # This frame's move is at most what the last frame promised: the spring's speed with it, so that it does not
        # build up behind the limit.
        if (CFY[b] - was > lim) { CFY[b] = was + lim; if (CFV[b] > lim / dt) CFV[b] = lim / dt }
        if (was - CFY[b] > lim) { CFY[b] = was - lim; if (CFV[b] < -lim / dt) CFV[b] = -lim / dt }
        CFY[b] = clamp(CFY[b], 0.05, GRID - 0.05)
      }
    }
    CPY[b] = int(CFY[b] * CURVEQ + 0.5) / CURVEQ  # whole steps: a key whose piece did not really move is not resent
  }
  CFON = 1; CFAT = NOW; CFRENDER = RENDERS
  CSN = 0
  d = curvePath(CPX, CPY, 8, 1)
  # Every stroke finds its keys with the widest glow's reach (half its width) and the sampling's error. A key the
  # glow does not reach gets no update for it (was + 0.12 around the samples: one Curve update in eight was for a
  # key that shows nothing of the line).
  CREACH = CWID[0] / 200 + 0.03
  # The move the next frame may make: the fastest speed over the interval to it (LASTIV, the one this frame
  # promises); the idle line hardly moves. CREAL: the reach plus that move (a Catmull-Rom point moves the line by at
  # most 1.25 times its own move, and only up or down) and a step of the drawing grid: a key the line does not reach
  # but may reach by the next frame holds the real line (invisible), so that when it lights up it glides from the
  # line its neighbours had.
  CMOVE = IDLE || hold ? 0.1 : CURVEV * (GRID - 0.7) * LASTIV
  if (CMOVE > CMOVEMAX) CMOVE = CMOVEMAX
  CREAL = CREACH + 1.25 * CMOVE + 0.03
  bbox(CSX, CSY, CSN, CREAL)
  # The samples run left to right: each band looks only at the pieces between those within its reach and the one
  # either side.
  for (b = 0; b < 8; b++) {
    CSLO[b] = CSN; CSHI[b] = -1
    for (k = 0; k < CSN; k++) if (CSX[k] > b - CREACH && CSX[k] < b + 1 + CREACH) { if (k < CSLO[b]) CSLO[b] = k; CSHI[b] = k }
    if (CSLO[b] > 0) CSLO[b]--
    if (CSHI[b] >= 0 && CSHI[b] < CSN - 1) CSHI[b]++
  }
  for (k = 0; k < 4; k++) {
    setSlot(k, d, PRAD[k], 0, CWID[k], CREST[k] + CFLASH[k] * BEATENV, "B", BX0, BY0, BX1, BY1)
    SLCURVE[k] = 1
  }
}
# The curve as one key draws it: only its own piece of the line. The key cuts the same cubics everyone draws out of
# the whole line (at x = b - KWE .. b + 1 + KWE, the window and a margin wider than the glow's half width), so the
# pieces of neighbouring keys are one line where they overlap. The cuts are at fixed t of fixed segments (a point's
# x never moves), so a cut of the glide between two frames is the glide between their cuts: the phone draws the
# same line it would draw from the whole path. The 16 cubics stay (the other effects' slots have them): segments
# outside the cut collapse onto its ends. Each key gets only its own short piece of the long line, never the whole
# line left for the key's window to hide. A key the line cannot reach before the next frame
# (real = 0) gets its piece laid flat along the edge the line passes (above or below the key), just outside the
# window: invisible, and the same frame for as long as the line stays on that side.
function bez(a, b, c, d, t,    u) { u = 1 - t; return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d }
# The four x of segment i (as curvePath draws it: its ends clamp the tangent's neighbours).
function segX(i,    a, c) {
  a = i > 0 ? i - 1 : 0; c = i + 2 < 8 ? i + 2 : 7
  SGX0 = CPX[i]; SGX1 = CPX[i] + (CPX[i + 1] - CPX[a]) / 6; SGX2 = CPX[i + 1] - (CPX[c] - CPX[i]) / 6; SGX3 = CPX[i + 1]
}
# t where segment i reaches x (x grows along every segment).
function segT(i, x,    lo, hi, m, n) {
  segX(i); lo = 0; hi = 1
  for (n = 0; n < 40; n++) { m = (lo + hi) / 2; if (bez(SGX0, SGX1, SGX2, SGX3, m) < x) lo = m; else hi = m }
  return (lo + hi) / 2
}
# Key column b's cut: first segment KWA from t KWTA, last KWB up to t KWTB (constant: the points' x never move).
function keyWindow(b,    xa, xb, i) {
  if (b in KWA) return
  xa = b - KWE; xb = b + 1 + KWE
  if (xa <= CPX[0]) { KWA[b] = 0; KWTA[b] = 0 }
  else { for (i = 0; i < 6 && CPX[i + 1] <= xa; i++) ; KWA[b] = i; KWTA[b] = segT(i, xa) }
  if (xb >= CPX[7]) { KWB[b] = 6; KWTB[b] = 1 }
  else { for (i = 6; i > 0 && CPX[i] >= xb; i--) ; KWB[b] = i; KWTB[b] = segT(i, xb) }
}
# De Casteljau: the part [t0, t1] of the cubic a b c d into Q0..Q3.
function cut(a, b, c, d, t0, t1,    ab, bc, cd, abc, bcd, s) {
  if (t0 > 0) {
    ab = a + (b - a) * t0; bc = b + (c - b) * t0; cd = c + (d - c) * t0
    abc = ab + (bc - ab) * t0; bcd = bc + (cd - bc) * t0
    a = abc + (bcd - abc) * t0; b = bcd; c = cd
    t1 = (t1 - t0) / (1 - t0)
  }
  if (t1 < 1) {
    ab = a + (b - a) * t1; bc = b + (c - b) * t1; cd = c + (d - c) * t1
    abc = ab + (bc - ab) * t1; bcd = bc + (cd - bc) * t1
    b = ab; c = abc; d = abc + (bcd - abc) * t1
  }
  Q0 = a; Q1 = b; Q2 = c; Q3 = d
}
function keyCurve(near, b, y0,    m, i, a, c, y, key, t, ia, ib, x0, x1, x2, x3, y1, y2, y3, ax, ay, bx, by, d, back) {
  m = 0.3
  keyWindow(b); ia = KWA[b]; ib = KWB[b]
  if (!near) {
    # Which side: the line's height at the key's middle (between the two points around it).
    for (i = 0; i < 6 && CPX[i + 1] < b + 0.5; i++) ;
    t = clamp((b + 0.5 - CPX[i]) / (CPX[i + 1] - CPX[i]), 0, 1)
    y = CPY[i] + (CPY[i + 1] - CPY[i]) * t > y0 + 0.5 ? y0 + 1 + m : y0 - m
    key = y
    for (i = 0; i < 8; i++) KY[i] = y
  } else {
    key = 1
    for (i = 0; i < 8; i++) KY[i] = CPY[i]
    for (i = ia > 0 ? ia - 1 : 0; i <= ib + 2 && i < 8; i++) key = key " " KY[i]
  }
  if (KCK[b, y0] == key) return KCV[b, y0]
  KCK[b, y0] = key
  # The cut pieces, segment by segment; outside the cut a segment collapses onto the cut's nearer end.
  for (i = ia; i <= ib; i++) {
    a = i > 0 ? i - 1 : 0; c = i + 2 < 8 ? i + 2 : 7
    segX(i)
    cut(SGX0, SGX1, SGX2, SGX3, i == ia ? KWTA[b] : 0, i == ib ? KWTB[b] : 1)
    KQX0[i] = Q0; KQX1[i] = Q1; KQX2[i] = Q2; KQX3[i] = Q3
    cut(KY[i], KY[i] + (KY[i + 1] - KY[a]) / 6, KY[i + 1] - (KY[c] - KY[i]) / 6, KY[i + 1], i == ia ? KWTA[b] : 0, i == ib ? KWTB[b] : 1)
    KQY0[i] = Q0; KQY1[i] = Q1; KQY2[i] = Q2; KQY3[i] = Q3
  }
  ax = KQX0[ia]; ay = KQY0[ia]; bx = KQX3[ib]; by = KQY3[ib]
  FP[0] = pt(ax, ay); d = "M" FP[0]; back = ""
  for (i = 0; i < 7; i++) {
    if (i < ia) { FQ1[i] = FQ2[i] = FP[i + 1] = FP[0] }
    else if (i > ib) { FQ1[i] = FQ2[i] = FP[i + 1] = pt(bx, by) }
    else { FQ1[i] = pt(KQX1[i], KQY1[i]); FQ2[i] = pt(KQX2[i], KQY2[i]); FP[i + 1] = pt(KQX3[i], KQY3[i]) }
    d = d "C" FQ1[i] " " FQ2[i] " " FP[i + 1]
    back = "C" FQ2[i] " " FQ1[i] " " FP[i] back
  }
  d = d "C" FP[7] " " FP[7] " " FP[7] back
  return KCV[b, y0] = d "C" FP[0] " " FP[0] " " FP[0] "Z"
}

# MARK: Keys

# The picture of one key (without its control column part), inside the group that turns it with the phone.
#
# Each of the four slot elements of a key is parked (0: a constant invisible point), placed (1: at its real shape,
# invisible — it appears on the next frame), shown (2) or leaving (3: invisible where it was, until its fade is
# over). So a slot never flies across the picture, and a line never morphs into a blob or back: a slot of the
# other kind waits until the old one has faded (a curve <-> blob switch holds every new slot until KINDHOLD).
# SNAP: a Bars key that must become completely full or empty lands there at once — while it glides, the key above
# is already filling and the bar shows a gap.
function picture(b, lv, idx,    k, W, near, P, S, g, p, cd, cn, cr, so, xf, glow, top, h, x, y, base) {
  PDEFS = "<defs>"; PTAGS = ""; cd = ""; cn = ""; cr = 0; KNEAR[idx] = 0
  for (k = 0; k < 4; k++) {
    W = ""; near = 0; g = PRAD[k]; p = ""
    if (SL[k]) {
      # The four strokes share one reach; cr: the key holds the real line (near, or may be on the next frame).
      if (SLCURVE[k]) { if (cn == "") { cn = touches(k, b, lv, CREACH); cr = cn ? 1 : touches(k, b, lv, CREAL) }; near = cn }
      else near = touches(k, b, lv)
      if (near) KNEAR[idx] = 1
      g = SLG[k]
      if (SLCURVE[k]) {
        W = "c"
        if (cd == "") cd = keyCurve(cr, b, lv)
        # Away from the line the piece is transparent (constant, so a beat does not resend the deck), not only parked
        # outside the key's window.
        so = cr ? SLSO[k] : 0
        p = stagp(k, cd, 0, BSTROKE[b, k], SLSW[k], so)
      } else {
        if (near) W = "b"
        p = stagp(k, SLD[k], SLFO[k], SLST[k], SLSW[k], SLSO[k])
      }
    }
    P = KK[idx, k]; S = KS[idx, k] + 0
    if (S == 2 && P != W) {
      # Shown, but not any more: a blob that moved away fades on its way out; anything else fades where it is.
      xf = W != "" || NOW < KINDHOLD
      if (!xf && P == "b" && SL[k] && !SLCURVE[k]) { KG[idx, k] = g; KP[idx, k] = p }
      put(k, KG[idx, k], KP[idx, k], 0)
      KS[idx, k] = 3; KFADE[idx, k] = NOW + (xf ? XF : BASEDUR)
      if (xf) KEYXF = 1
      continue
    }
    if (S == 3) {
      if (W != "" && W == P) { put(k, g, p, 0); KG[idx, k] = g; KP[idx, k] = p; KS[idx, k] = 1; continue }
      if (NOW < KFADE[idx, k] || (W != "" && NOW < KINDHOLD)) { put(k, KG[idx, k], KP[idx, k], 0); continue }
      S = 0
    }
    if (S == 1 && P != W) S = 0
    if (W == "" || (S == 0 && NOW < KINDHOLD)) { put(k, PRAD[k], PTAGP[k], 0); KK[idx, k] = ""; KS[idx, k] = 0; continue }
    KG[idx, k] = g; KP[idx, k] = p; KK[idx, k] = W
    if (S == 0) { put(k, g, p, 0); KS[idx, k] = 1; PLACED++; continue }
    put(k, g, p, 1); KS[idx, k] = 2
    if (near && S == 2) KEYFLASH = 1                  # a slot that only now appears fades in, it does not flash
  }
  glow = 0; top = 1; h = 0
  if (!POWER) base = BASEOFF
  else if (EFFECT == 0) {
    base = BASEBARS[b]
    if (lv <= TOPK[b]) { glow = GLOW[b]; h = lv < TOPK[b] ? 1 : FILL[b]; top = lv >= HOTK[b] }
  } else base = BASEOTHER[b]
  SNAPPED = POWER && EFFECT == 0 && !IDLE && !SWITCHING && NOW >= TRANSUNTIL && PF[idx] >= 0 && PF[idx] != h && (h == 0 || h == 1)
  PF[idx] = h
  x = b * 100; y = (WT - 1 - lv) * 100; if (h < LTMIN) h = LTMIN
  # The unlit key and its lit part, from the key's bottom as high as h (a dark key keeps the glow of a bar's top,
  # invisible: a key the bar grows into only grows, the one it falls out of only empties); then the four slots.
  # Portrait turns the key's picture a quarter clockwise about its centre: the keys still join, bass at the top,
  # each bar growing from the left.
  return PDEFS "<radialGradient id='kg' cx='0.5' cy='0.5' r='" GLOWR "'>" (top ? GLOWT[b] : GLOWB[b, lv]) "</radialGradient>" \
    "</defs><g transform='rotate(" ROT " " (x + 50) " " (y + 50) ")'><rect id='bs' x='" x "' y='" y "' width='100' height='100' fill='" base "'/>" \
    "<rect id='lt' x='" x "' y='" n1(y + 100 - h * 100) "' width='100' height='" n1(h * 100) "' fill='url(#kg)' opacity='" n2(glow) "'/>" PTAGS "</g>"
}
function fitted(text,    i, em, c, s) {
  em = 0
  for (i = 1; i <= length(text); i++) { c = substr(text, i, 1); em += (c in CAPW) ? CAPW[c] : 0.7 }
  if (em < 0.1) em = 0.1
  s = int(84 / em * 2) / 2
  return s > 13 ? s : 13
}
# The control column (band 7: the rightmost column in landscape, the bottom row in portrait; upright in both):
# power at the top, the effect and the theme under it, the logo mark at the bottom — on the iPad's 6-level grid two
# plain keys of the panel between the theme and the logo. So power is in the corner and the logo at the other end
# on both devices. A key keeps one set of elements in both grids, whatever its part: key 7/3 is power on the
# phone's grid and the theme on the iPad's, so it carries the power glyph and a name; the part it does not play is
# invisible (roles: rolePart).
function rolePart(lv) { return lv == GRID - 1 ? "pw" : lv == GRID - 2 ? "fx" : lv == GRID - 3 ? "th" : lv == 0 ? "mk" : "" }
function control(lv,    shown, off, top, tag, role, cx, cy, r, dx, dy, d, isfx, txt, fs, big, op, i, h) {
  shown = POWER && COLUMN; off = !POWER; role = rolePart(lv)
  top = (WT - 1 - lv) * 100; cx = 750
  tag = "<rect id='pn' x='700' y='" top "' width='100' height='100' fill='#17181E' opacity='" (shown ? 1 : 0) "'/>"
  if (lv == 3 || lv == 5) {
    # A ring open at the top and a bar through the gap.
    cy = top + 54; r = 19; dx = r * cos(55 * PI / 180); dy = r * sin(55 * PI / 180)
    d = "M" n1(cx + dx) " " n1(cy - dy) "A" r " " r " 0 1 1 " n1(cx - dx) " " n1(cy - dy) "M" cx " " (cy - r - 5) "L" cx " " (cy - 3)
    op = role == "pw" ? (shown ? 1 : off ? 0.55 : 0) : 0
    tag = tag "<path id='pw' d='" d "' fill='none' stroke='#FF5E7E' stroke-width='6.5' stroke-linecap='round' opacity='" op "'/>"
  }
  if (lv >= 1 && lv <= 4) {
    # The name: the effect on keys 7/2 and 7/4, the theme on 7/1 and 7/3 (shown only where it is the key's part).
    isfx = lv == 2 || lv == 4
    txt = isfx ? ENAME[EFFECT] : TNAME[THEME]
    big = isfx ? 20 : 17; fs = fitted(txt); if (fs > big) fs = big
    op = shown && role == (isfx ? "fx" : "th") ? 1 : 0
    tag = tag "<text id='" (isfx ? "fx" : "th") "' x='750' y='" (top + 51) "' font-size='" fs "' font-weight='bold' text-anchor='middle' dominant-baseline='middle' fill='" (isfx ? "#FFFFFF" : TLABEL[THEME]) "' opacity='" op "'>" txt "</text>"
  }
  if (lv == 0) {
    # The logo mark: faint on the calm key, bright when the visualizer is off — the one thing on a dark deck.
    op = off ? 0.9 : shown ? 0.5 : 0
    for (i = 0; i < 3; i++) { h = MH[i]; tag = tag "<rect id='m" i "' x='" (cx - 23 + i * 17) "' y='" (top + 70 - h) "' width='12' height='" h "' rx='3' fill='" MARK[i] "' opacity='" op "'/>" }
  }
  return tag
}
# Every key the grid shows: prints an update-button body for every one whose frame changed (the keys the grid does
# not show are neither drawn nor sent: an iPhone does not show levels 4 and 5). The glide length is the
# frame's, except on keys that changed for their own reason: the control column's part of a band-7 key (short, it
# answers a tap), a bar key snapping full or empty, a beat's flash (a short attack, so the peak lands on the beat),
# a key whose slot fades between a curve and blobs.
function render(   b, lv, idx, pic, svg, d, ctl, snap, body, nl, i, probe, v, t, lo) {
  RENDERS++
  computeSlots()
  PLACED = 0; NCHG = 0; nl = 0; probe = ""
  # Bars: each band's height, the key holding its top (TOPK, -1: none; FILL of it lit, up to 1 at a whole key's top)
  # and the lowest key that glows as the top (HOTK: TOPK, or the key under it until FILL reaches BARHYS), at GLOW.
  # The idle look lights the bottom key alone, whole and as softly as its calm height.
  for (b = 0; b < 8; b++) {
    if (IDLE) BVAL[b] = int((0.3 + 0.2 * (0.5 + 0.5 * sin(CLOCK * 0.9 + b * 0.8))) * 50 + 0.5) / 50
    else BVAL[b] = int((BARON ? BARY[b] : LV[b] * GRID) * BARQ + 0.5) / BARQ    # GRID keys high, BARQ steps per key
    if (!POWER || EFFECT != 0) { TOPK[b] = HOTK[b] = -1; GLOW[b] = 0; continue }
    if (IDLE) { TOPK[b] = HOTK[b] = 0; FILL[b] = 1; GLOW[b] = BVAL[b]; continue }
    v = BVAL[b]; t = v < 0.001 ? -1 : int(v - 0.001)
    TOPK[b] = t; FILL[b] = v - t; GLOW[b] = 1
    lo = FILL[b] > BARHYS - 0.001 ? t : t - 1
    if (HOTK[b] > t) HOTK[b] = t; else if (HOTK[b] < lo) HOTK[b] = lo
  }
  if (ORCH) delete FROZEN
  ROT = PORTRAIT ? 90 : 0
  for (b = 0; b < 8; b++) for (lv = 0; lv < NLV; lv++) {
    idx = b * NLV + lv; snap = 0; KEYFLASH = 0; KEYXF = 0
    # A key past the grid the phone shows, or one it does not list: nothing to draw.
    if (lv >= GRID || ID[idx] == "-") { CUR[idx] = ""; CHG[idx] = 0; continue }
    ctl = b == 7 ? control(lv) : ""
    # The picture under the control column while it is shown: held, not sent again (nobody sees it).
    if (b == 7 && COLUMN && (idx in FROZEN)) pic = FROZEN[idx]
    else {
      pic = picture(b, lv, idx); snap = SNAPPED && !(b == 7 && (COLUMN || COLCH))
      if (b == 7 && COLUMN) FROZEN[idx] = pic; else delete FROZEN[idx]
    }
    if (SWITCHING) d = KEYXF ? XF : SWDUR
    else if (SETTLING || ORCH) d = BASEDUR
    else if (b == 7 && ctl != LASTCTL[idx]) d = CTLDUR
    else if (snap) d = SNAPDUR
    # No short attack on the keys a beat lights: one blob spans several keys, and keys of one shape gliding at
    # different speeds tear it apart for the length of the glide (seen on an old iPad with loud music).
    else d = BASEDUR
    LASTCTL[idx] = ctl
    d = n2(d)
    svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='" (b * 100) " " ((WT - 1 - lv) * 100) " 100 100'>" pic ctl "</svg>"
    CUR[idx] = svg; CURDUR[idx] = d
    if (svg != LAST[idx]) {
      LAST[idx] = svg; CHG[idx] = 1; NCHG++
      body = "{\"cellId\":\"" ID[idx] "\",\"svg\":{\"source\":\"" svg "\",\"duration\":" d ",\"fit\":\"stretch\",\"easing\":\"linear\"}}"
      # The order the loop posts them in. First, on the iPad's grid, one of its own keys (levels 4 and 5): the loop
      # posts the first body alone, and its answer says whether the phone still shows them (and the page) before the
      # rest go out together. Then, in Curve, the keys the line lights, band by band, so that they reach the phone
      # close together; the ones it does not light (a piece laid flat, or held for the next frame) after them.
      if (FACES) ;
      else if (probe == "" && GRID == 6 && lv >= 4) probe = body
      else if (EFFECT != 3 || KNEAR[idx]) NEARB[++NN] = body
      else LATER[++nl] = body
    } else CHG[idx] = 0
  }
  if (probe != "") out(probe)
  for (i = 1; i <= NN; i++) out(NEARB[i])
  for (i = 1; i <= nl; i++) out(LATER[i])
  NN = 0
}

# The phone shows the other grid (an iPad after an iPhone, or back). The world keeps its width and takes the new
# height: the lava keeps its place in proportion, the curve starts where the levels are, and keys the old grid did
# not show start from what the phone has for them (their saved face or a frame of long ago): every slot as if
# parked, so it is placed invisibly before it shows. Every shown key is sent again.
function setGrid(g,    f, k, b, lv, idx) {
  f = g / GRID
  for (k = 0; k < 4; k++) { LY[k] *= f; LVY[k] *= f; DLY[k] *= f; DLVY[k] *= f }
  for (b = 0; b < 8; b++) { BARY[b] *= f; BARV[b] *= f; BVAL[b] *= f }
  for (b = 0; b < 8; b++) for (lv = GRID; lv < g; lv++) {
    idx = b * NLV + lv
    for (k = 0; k < 4; k++) { KS[idx, k] = 0; KK[idx, k] = "" }
    PF[idx] = -1; LASTCTL[idx] = ""; delete FROZEN[idx]
  }
  GRID = g; GS = g / 4; LRS = g == 6 ? 1.2 : 1; AMS = g == 6 ? 1.35 : 1; AMY = g == 6 ? 1.2 : 1.12
  CFON = 0
  delete LAST
}

# MARK: Levels

# A new answer: its 20 bands onto the 8 key bands (half the loudest of the band's share, half their weighted mean) and
# the bass meter, each shaped by its own automatic gain (AGQ and the rest, in BEGIN) into LV[0..7] and BASS.
function levels(aud,    dt, b, k, mx, sum, w, v, e, top, f, lo) {
  dt = NOW - AGLAST; AGLAST = NOW
  e = 0
  for (b = 0; b < 8; b++) {
    mx = 0; sum = 0; w = 0
    for (k = MAPFROM[b]; k <= MAPTO[b]; k++) { v = clamp($(16 + k) / 40, 0, 1); if (v > mx) mx = v; sum += v * MAPW[b, k]; w += MAPW[b, k] }
    RAWL[b] = 0.5 * mx + 0.5 * sum / w
    if (RAWL[b] > e) e = RAWL[b]
  }
  RAWL[8] = clamp($13 / 40, 0, 1)
  if (dt > AGQUIET) AGSILENT = AGQUIET + 1       # no answer for that long (the page away, power off): as a silence
  if (!aud || e < AGINFO) AGSILENT += dt < 0.5 ? dt : 0.5
  else {
    # Music after a silence (or the first music): the headroom starts at the top of the scale, then adapts quickly.
    if (AGSTART || AGSILENT > AGQUIET) {
      for (b = 0; b <= 8; b++) if (AGH[b] < AGRESET) AGH[b] = AGRESET
      AGWARMAT = NOW; AGSTART = 0; dt = 0
    }
    AGSILENT = 0
    if (dt > 0.5) dt = 0.5
    f = NOW - AGWARMAT - AGHOLD
    f = f < 0 ? 0 : f < AGWARM ? 1 + AGWARMK * (1 - f / AGWARM) : 1
    top = 0
    for (b = 0; b <= 8; b++) {
      if (RAWL[b] >= AGINFO) AGH[b] += RAWL[b] > AGH[b] ? AGUP * dt : -AGDOWN * f * dt
      if (b < 8 && AGH[b] > top) top = AGH[b]
    }
    for (b = 0; b <= 8; b++) {
      lo = b < 8 && AGKAPPA * top > AGFLOOR ? AGKAPPA * top : AGFLOOR
      AGH[b] = clamp(AGH[b], lo, AGRESET)
    }
  }
  for (b = 0; b < 8; b++) LV[b] = shaped(RAWL[b] / AGH[b])
  BASS = shaped(RAWL[8] / AGH[8])
}
# A level against its headroom (x = level / H) as a share of the height: AGAT x ^ AGGAMMA up to H, then to the top
# within AGHEAD, the slope carrying on at H.
function shaped(x,    u) {
  if (x <= 1) return AGAT * x ^ AGGAMMA
  u = x - 1
  return u >= AGHEAD ? 1 : AGAT + AGAT * AGGAMMA * u + AGC2 * u * u
}
# Bars: every drawn frame moves each band's height (keys) towards its level, a critically damped spring (BARWUP up,
# BARWDN down); the velocity carries from frame to frame. After a pause (idle, another effect, the page away) the
# height starts where it was drawn last.
function barStep(   b, dt, y, x, v, e, w) {
  dt = NOW - BARAT; BARAT = NOW
  for (b = 0; b < 8; b++) {
    y = LV[b] * GRID
    if (!BARON || dt > 0.4) { BARY[b] = BVAL[b] + 0; BARV[b] = 0; continue }
    w = y > BARY[b] ? BARWUP : BARWDN
    x = BARY[b] - y; v = BARV[b]; e = exp(-w * dt)
    BARY[b] = y + (x + (v + w * x) * dt) * e
    BARV[b] = (v - w * (v + w * x) * dt) * e
    if (BARY[b] < 0) { BARY[b] = 0; if (BARV[b] < 0) BARV[b] = 0 }
    if (BARY[b] > GRID) { BARY[b] = GRID; if (BARV[b] > 0) BARV[b] = 0 }
  }
  BARON = 1
}

# MARK: A tick

# Seconds between frames with music: the effect's own, or for Bars, Lava and Curve paced by the keys their frames
# change.
function musicInterval(   iv) {
  if (EFFECT == 1) return GRID == 6 ? AMIV6 : ACTIV[1]    # the iPad's 48 keys: fewer frames, about the same updates
  iv = EFFECT == 3 ? CURVECHG / CURVEBUDGET : EFFECT == 2 ? LAVACHG / LAVABUDGET : BARCHG / UPDBUDGET
  if (iv <= ACTIV[EFFECT]) return ACTIV[EFFECT]
  return EFFECT == 0 ? int(iv * 200 + 0.999) / 200 : int(iv * 100 + 0.999) / 100
}
function tick(   dt, b, k, mx, sum, w, v, iv, ivn, idleiv, act, sw, tap, colch, orch, forced, settling, draw, nxt, gap, aud, beat, behind, sleeping, regular, due, onbeat) {
  NOW = $2 + 0
  dt = LASTNOW < 0 ? 1 / 12 : NOW - LASTNOW
  dt = clamp(dt, 0, 0.5); LASTNOW = NOW
  EFFECT = int($3) % 4; if (EFFECT < 0) EFFECT = 0
  k = int($4) % NT; if (k < 0) k = 0
  if (k != THEME) setTheme(k)
  POWER = $5 != 0; COLUMN = $6 != 0; sw = $7 != 0; tap = $8 != 0; behind = $9 != 0; PORTRAIT = $10 != 0
  if (($11 == 6 ? 6 : 4) != GRID) setGrid($11 == 6 ? 6 : 4)
  aud = $12 != 0; beat = $15 != 0
  # The levels move only with a new answer: the last one again (a Bars frame between two requests) is not news.
  if (NF < 36 || $36 != 0) levels(aud)
  ENERGY = 0; for (b = 0; b < 8; b++) ENERGY += LV[b] / 8
  BEATENV -= dt * 4; if (BEATENV < 0) BEATENV = 0
  if (beat) { BEATENV = 1; PENDBEAT = 1; lavaKick() }
  SILENT = aud ? 0 : SILENT + dt
  IDLE = SILENT > 1 ? 1 : 0                     # "audible" holds 2 s by itself: idle about 3 s after the music stops
  if (IDLE && !IDLEPREV) IDLESINCE = NOW
  IDLEPREV = IDLE
  if (tap) IDLESINCE = NOW                      # a touch wakes the idle look for another while
  # After SLEEPAFTER seconds of idle the picture holds still as it was last drawn (the phone stops gliding); the
  # levels are still asked for, so music wakes it at once.
  sleeping = POWER && IDLE && NOW - IDLESINCE >= SLEEPAFTER
  if (sleeping && !SLEEPING) {
    CLOCK = DCLOCK; for (k = 0; k < 4; k++) { LX[k] = DLX[k]; LY[k] = DLY[k]; LVX[k] = DLVX[k]; LVY[k] = DLVY[k]; LR[k] = DLR[k]; LFL[k] = DLFL[k] }
  }
  # Slots placed on the last frame must show before the picture holds still (going to sleep, or a turn or the other
  # grid while asleep).
  if (sleeping && PLACED > 0) SLEEPSETTLE = 1
  SLEEPING = sleeping
  if (!SLEEPING) { CLOCK += dt; lavaStep(dt) }
  if (beat) lavaFlash()
  act = musicInterval() * (behind ? 3 : 1)
  idleiv = IDLEIV[EFFECT] * (behind ? 3 : 1)
  iv = IDLE ? idleiv : act
  if (NOW < TRANSUNTIL && act < iv) iv = act    # a switch or a turn plays out at the music rate, then idle resumes
  sw = sw || EFFECT != LASTEFFECT
  colch = COLUMN != WASCOL; orch = PORTRAIT != WASPORT || GRID != WASGRID    # a turn, or the other grid
  settling = IDLE && !WASIDLE
  forced = tap || colch || orch || FORCE
  # Curve's interval grew since the last frame: that frame's glide was made for the old one, so this frame comes
  # when promised (a later one would leave the line standing still), and the new interval starts from it.
  due = EFFECT != 1 && !IDLE && LASTIV > 0 && LASTIV < iv ? LASTIV : iv
  # Lava draws a beat at once (not closer than LAVABEATGAP to the frame before); the next frame comes an interval
  # after it.
  onbeat = EFFECT == 2 && POWER && PENDBEAT && !IDLE && NOW - LASTDRAW >= LAVABEATGAP && NOW - LASTDRAW < due - 0.02
  draw = forced || sw || settling || SLEEPSETTLE || onbeat || (!SLEEPING && NOW - LASTDRAW >= due - 0.02)
  if (!POWER && !forced && !sw) draw = 0
  nxt = !POWER ? 0 : IDLE ? (iv < 0.25 ? iv : 0.25) : iv
  if (EFFECT == 2 && POWER && !IDLE && nxt > LAVAPOLL) nxt = LAVAPOLL    # Lava listens for the beat between frames
  # A tick that came early (the loop's schedule runs on after a tick that woke late): the next one when this frame
  # is due, not a whole interval later — the last glides end at the interval and a bit, then the keys would stand.
  if (!draw && POWER && !IDLE && !SLEEPING && LASTDRAW + due - NOW < nxt) nxt = n2(LASTDRAW + due - NOW + 0.005)
  if (POWER && nxt < 0.01) nxt = 0.01                # 0 would mean "no tick needed" (power off)
  if (DUMP != "") dumpTick(dt)
  out("N " nxt " " IDLE " " (draw ? 1 : 0) " " SLEEPING)
  if (!draw) return
  # A frame glides over the measured interval and a bit more, so the next frame always takes over a live glide:
  # one that ends early leaves the key standing still until the next frame, which reads as stutter. Frames drawn
  # off the beat (a tap, the keyframe, a turn) keep that length and do not count as a measurement.
  gap = NOW - LASTDRAW
  if (iv != IVNOM || gap > 3 * iv) { IVNOM = iv; IVAVG = iv }
  else if (!forced && !sw && !settling && !onbeat) IVAVG += (gap - IVAVG) * 0.3
  # The glide covers the gap to the NEXT frame: the last frame of a switch or a turn in idle is followed by an
  # idle interval, not by another short one.
  # At least GLIDEPAD longer than the interval (a wake-up 10-20 ms late is common: 1.2 x the 45 ms of Bars would not
  # cover it), rounded up to the hundredth the body carries.
  ivn = IDLE && NOW + act >= TRANSUNTIL && !sw && !orch ? idleiv : iv
  REGDUR = (ivn == iv ? IVAVG : ivn); REGDUR = REGDUR * 1.2 > REGDUR + GLIDEPAD ? REGDUR * 1.2 : REGDUR + GLIDEPAD
  REGDUR = int(REGDUR * 100 + 0.999) / 100; if (REGDUR < 0.05) REGDUR = 0.05
  CTLDUR = act * 1.2 > 0.18 ? act * 1.2 : 0.18
  SWITCHING = sw; SETTLING = settling && !sw; ORCH = orch && !sw; COLCH = colch
  if (sw) {
    # A curve into blobs or back: the old slots fade out within one frame of the new effect, the next frame places
    # the new ones invisibly, the one after shows them.
    # Into Curve: the fade of round 3 (its frames were 0.2 s apart then), not one of its short frames.
    # Into Lava: its fade from before it drew up to 6 frames a second.
    XF = (EFFECT == 3 ? 0.2 : EFFECT == 2 ? 0.25 : ACTIV[EFFECT]) * 0.95; if (XF > XFADE) XF = XFADE
    if (LASTCLASS + kindOf(EFFECT, POWER) == 3) KINDHOLD = NOW + XF
    BASEDUR = SWDUR
    TRANSUNTIL = NOW + (NOW < KINDHOLD ? XF : SWDUR) + 2.5 * (EFFECT == 2 ? 0.25 : ACTIV[EFFECT])
  } else if (SETTLING) BASEDUR = REGDUR > 0.9 ? REGDUR : 0.9
  else if (ORCH) { BASEDUR = ORIENTDUR; TRANSUNTIL = NOW + ORIENTDUR + ACTIV[EFFECT] }
  else BASEDUR = REGDUR
  # Curve: the frame that shows the slots the last frame placed (after a switch, the other grid, a start, or
  # just before the picture holds still) fades the line in over SHOWDUR, as before its frames came faster, and the
  # frames after it glide at least until that fade is over (a shorter glide would cut it short).
  if (EFFECT == 3 && !sw) {
    if (PLACED > 0) SHOWUNTIL = NOW + (BASEDUR > SHOWDUR ? BASEDUR : SHOWDUR)
    if (NOW < SHOWUNTIL && BASEDUR < SHOWUNTIL - NOW) BASEDUR = SHOWUNTIL - NOW
  }
  # A turn or the other grid (every key glides ORIENTDUR), or a switch into Bars (SWDUR): the frames that follow within
  # that time glide until it is over. A key that changes on one of them would otherwise finish its turn early, ahead of
  # the keys that did not change — Bars draw 22 frames a second, so the tops of the bars would turn in 0.1 s and the
  # rest in 0.3 s.
  if (ORCH || (sw && EFFECT == 0)) HOLDUNTIL = NOW + BASEDUR
  else if (NOW < HOLDUNTIL && BASEDUR < HOLDUNTIL - NOW) BASEDUR = n2(HOLDUNTIL - NOW + 0.005)
  # A beat frame (Amoeba, Lava) glides like any other: a short attack on the keys a beat lights (it was 0.07 s on
  # Amoeba, 0.09 s on Lava) tore a blob that spans several keys apart for the length of the glide, and on the curve
  # it made the line jump and then stand still. ATTACK and LAVAATTACK are no longer used.
  BEATFRAME = PENDBEAT && !IDLE && (EFFECT == 1 || EFFECT == 2)
  LASTIV = iv; LASTDRAW = NOW; LASTEFFECT = EFFECT; LASTCLASS = kindOf(EFFECT, POWER); WASIDLE = IDLE; WASCOL = COLUMN
  WASPORT = PORTRAIT; WASGRID = GRID
  # A frame that shows the slots the last one placed, or places new ones (a switch, a start, the other grid), changes
  # many keys at once: not a measure of the pace.
  regular = !forced && !sw && !settling && !SLEEPSETTLE && !IDLE && PLACED == 0
  FORCE = 0; PENDBEAT = 0; SLEEPSETTLE = 0
  if (EFFECT == 0 && POWER && !IDLE) barStep(); else BARON = 0
  render()
  if (EFFECT == 3 && regular && PLACED == 0) CURVECHG = NCHG > CURVECHG ? NCHG : CURVECHG + (NCHG - CURVECHG) * 0.15
  if (EFFECT == 0 && regular) BARCHG += (NCHG - BARCHG) * (NCHG > BARCHG ? 0.2 : 0.1)
  if (EFFECT == 2 && regular) LAVACHG = NCHG > LAVACHG ? NCHG : LAVACHG + (NCHG - LAVACHG) * 0.15
  DCLOCK = CLOCK; for (k = 0; k < 4; k++) { DLX[k] = LX[k]; DLY[k] = LY[k]; DLVX[k] = LVX[k]; DLVY[k] = LVY[k]; DLR[k] = LR[k]; DLFL[k] = LFL[k] }
  if (DUMP != "") dumpFrame()
}
# The 48 saved faces: the calm idle look (Bars, not yet lit by anything: the bottom keys softly aglow), the same
# elements as every live frame. Drawn on the iPad's grid in landscape; the idle bars and the hidden column are the
# same on the phone's grid and, every key whole and its glow round, upright, so the phone's 32 keys look the same
# either way (a saved face cannot know the device or which way it stands).
# A still picture of a key (the Gallery's faces and cover): what shows and nothing else — no slot the frame keeps
# invisible, no gradient nothing uses, no element ids (a still never glides). tag: put before the gradients' ids, so
# the keys of one picture keep their own; "" for a key alone.
function still(svg, tag,    s, rest, body, i, j, gid) {
  s = svg
  gsub(/<path [^>]* opacity='0'\/>/, "", s)
  gsub(/<rect [^>]* opacity='0'\/>/, "", s)
  gsub(/<text [^>]* opacity='0'>[^<]*<\/text>/, "", s)
  rest = s; s = ""
  while ((i = index(rest, "<radialGradient id='")) > 0) {
    s = s substr(rest, 1, i - 1); rest = substr(rest, i)
    j = index(rest, "</radialGradient>") + 16
    body = substr(rest, 1, j); rest = substr(rest, j + 1)
    gid = substr(body, 21); gid = substr(gid, 1, index(gid, "'") - 1)
    if (index(s rest, "url(#" gid ")")) { sub("id='" gid "'", "id='" tag gid "'", body); s = s body }
  }
  s = s rest
  if (tag != "") gsub(/url\(#/, "url(#" tag, s)
  gsub(/<rect id='[a-z0-9]+' /, "<rect ", s); gsub(/<path id='[a-z0-9]+' /, "<path ", s)
  sub(/<defs><\/defs>/, "", s)
  return s
}

function faces(e, t, g,    idx) {
  FACES = 1; EFFECT = e % 4; setTheme(t % NT); POWER = 1; COLUMN = 0; IDLE = 1; CLOCK = 0; SWITCHING = 1
  ENERGY = 0; BASS = 0; BEATENV = 0; PORTRAIT = 0; NOW = 0; BASEDUR = SWDUR
  if (g != GRID) setGrid(g)
  render()
  for (idx = 0; idx < NKEY; idx++) if (CUR[idx] != "") out(CUR[idx])
}

# Bars standing at the heights hs (keys, from bass to treble) in Synthwave, on grid g, upright (portrait 1) or in
# landscape: every key's frame into CUR. Each bar as if it had just risen there (HOTK).
function stage(hs, portrait, g,    b, n) {
  FACES = 1; EFFECT = 0; setTheme(0); POWER = 1; COLUMN = 0; IDLE = 0; SWITCHING = 1; PORTRAIT = portrait; NOW = 0; BASEDUR = SWDUR
  if (GRID != g) setGrid(g)
  split(hs, n, " "); BARON = 1
  for (b = 0; b < 8; b++) { BARY[b] = n[b + 1] + 0; HOTK[b] = -1 }
  render()
}
# The regular frame (no switch, no turn: a bar key snaps, the rest glide BASEDUR, a Bars frame's glide at 22 a
# second) that moves the staged bars to the heights hs.
function restage(hs,    b, n) {
  SWITCHING = 0; SETTLING = 0; ORCH = 0; COLCH = 0; NOW = 1; BASEDUR = 0.07
  split(hs, n, " ")
  for (b = 0; b < 8; b++) BARY[b] = n[b + 1] + 0
  render()
}
# Eight fields from the k-th on, one string.
function eight(k,    s, i) { s = $k; for (i = k + 1; i < k + 8; i++) s = s " " $i; return s }
# The Gallery's sample (--faces): a moment of the live Bars, drawn by its own frame code at staged heights (whole
# keys; an iPhone shows the lowest four) on the iPad's grid in landscape. The Gallery shows the page turned and a
# screenshot of the deck upright, and one face cannot know which: at a whole height every key is whole, lit or not,
# its glow round about its centre (picture), so the same still reads either way. Only the live page, which knows
# how the phone stands, lights a top key part-way.
function sample(   idx) {
  stage("4 5 3 2 3 2 3 1", 0, 6)
  for (idx = 0; idx < NKEY; idx++) out(still(CUR[idx], ""))
}

# MARK: Synthetic music (dry and dump modes), in the agent's line format

function rnd() { SEED = (SEED * 16807) % 2147483647; return SEED / 2147483647 }
function tone(f, a,    x, k) {
  if (f < 35 || f >= 14000 || a <= 0) return
  x = log(f / 35) / LOGR - 0.5; if (x < 0) x = 0
  k = int(x); x -= k
  E[k] += a * (1 - x); if (k < 19) E[k + 1] += a * x
}
function noise(from, to, a,    k) { for (k = from; k <= to; k++) E[k] += a * (0.7 + 0.6 * rnd()) }
function synthStep(t,    tt, drums, bassm, lead, pad, arp, gain, tb, te, beatno, bar, eighth, root, f, env, k, v, loud) {
  for (k = 0; k < 20; k++) E[k] = 0
  tt = t - int(t / 50) * 50
  if (tt < 4) { drums = 0; bassm = 0; lead = 0.7; pad = 1; arp = 0; gain = 0.4 }
  else if (tt < 18) { drums = 1; bassm = 1; lead = 1; pad = 0.6; arp = 0; gain = 1 }
  else if (tt < 26) { drums = 0.35; bassm = 1; lead = 1; pad = 0.5; arp = 0; gain = 0.62 }
  else if (tt < 30) { drums = 0; bassm = 0; lead = 0.4; pad = 1; arp = 0; gain = 0.22 }
  else if (tt < 37) { drums = 0; bassm = 0; lead = 0; pad = 0; arp = 0; gain = 0 }
  else { drums = 1; bassm = 1; lead = 1; pad = 0.5; arp = 1; gain = 1 }
  if (gain > 0) {
    tb = t - int(t / 0.5) * 0.5; beatno = int(t / 0.5); bar = int(beatno / 4)
    te = t - int(t / 0.25) * 0.25; eighth = int(t / 0.25)
    if (drums > 0) {
      env = exp(-tb * 7.5) * drums
      tone(48 + 90 * exp(-tb * 30), 1.3 * env); tone(96, 0.45 * env)
      if (beatno % 2 == 1) { noise(6, 15, 0.3 * exp(-tb * 18) * drums); tone(190, 0.5 * exp(-tb * 14) * drums) }
      noise(15, 19, 0.4 * exp(-te * 55) * drums)
      if (beatno != SLASTBEAT) { SLASTBEAT = beatno; SBEAT = 1; SBEATAT = t }
    }
    root = ROOT[bar % 4]
    if (bassm > 0) { env = (0.55 + 0.45 * exp(-te * 5)) * 0.75 * bassm; tone(root, env); tone(2 * root, 0.6 * env); tone(3 * root, 0.35 * env); tone(4 * root, 0.25 * env) }
    if (lead > 0) { f = SCALE[(eighth * 5 + int(eighth / 3) + bar * 2) % 10]; env = clamp(te * 200, 0, 1) * exp(-te * 3.5) * 0.6 * lead; tone(f, env); tone(2 * f, 0.4 * env); tone(3 * f, 0.2 * env) }
    if (pad > 0) for (k = 0; k < 3; k++) tone(root * (4 + k), 0.2 * (0.7 + 0.3 * sin(t * 0.7 + k)) * pad)
    if (arp > 0) { f = ARP[eighth % 4]; tone(f, 0.5 * exp(-te * 9) * arp); tone(2 * f, 0.2 * exp(-te * 9) * arp) }
    for (k = 0; k < 20; k++) E[k] = E[k] * gain * (0.94 + 0.12 * rnd())
  }
  # Like the agent: against a reference, rising at once, falling 2.4 per second, gated; peaks held until asked.
  loud = 0
  for (k = 0; k < 20; k++) {
    v = E[k] / (E[k] + 0.25) * 1.25; if (v > 1) v = 1
    v = v * v * (3 - 2 * v); if (v < 0.03) v = 0
    if (v > loud) loud = v
    SLV[k] = v > SLV[k] - 2.4 * SSTEP ? v : SLV[k] - 2.4 * SSTEP
    if (SLV[k] > SPK[k]) SPK[k] = SLV[k]
  }
  v = (E[0] + E[1] + E[2] + E[3] + E[4]) / 2.5; v = v / (v + 0.3) * 1.3; if (v > 1) v = 1
  SBASSL = v > SBASSL - 2.4 * SSTEP ? v : SBASSL - 2.4 * SSTEP
  if (SBASSL > SBASSPK) SBASSPK = SBASSL
  if (loud > 0) SLOUD = t
}
function synthLine(t,    k, s, p) {
  while (STIME + SSTEP <= t + 1e-9) { STIME += SSTEP; synthStep(STIME) }
  p = 35 * (1 - (t - SBEATAT) / 0.25); if (p < 0) p = 0
  s = "ok " (t - SLOUD < 2 ? 1 : 0) " " int(SBASSPK * 40 + 0.5) " " int(p + 0.5) " " (SBEAT ? 1 : 0)
  SBEAT = 0; SBASSPK = SBASSL
  for (k = 0; k < 20; k++) { s = s " " int(SPK[k] * 40 + 0.5); SPK[k] = SLV[k] }
  return s
}

# MARK: Recorded answers (dry and dump modes)

# Lines "<unix time> <state> <audible> <bass> <pulse> <beat> <l0> .. <l19>" in time order; a pause over 1 s in the
# recording is closed to the usual interval (the median, from whole milliseconds), and the whole plays again after it.
function loadReplay(file,    line, f, n, prev, t, d, i, k, hist, c, med) {
  n = 0; t = 0; prev = ""
  while ((getline line < file) > 0) {
    if (split(line, f, " ") != 26) continue
    if (prev != "") { d = f[1] - prev; if (d > 0 && d <= 1) { t += d; hist[int(d * 1000)]++ } else RPGAP[n] = 1 }
    prev = f[1]
    RPT[n] = t; RPS[n] = f[2]
    for (k = 1; k <= 24; k++) RPF[n, k] = f[k + 2] + 0
    n++
  }
  close(file)
  c = 0; med = 111
  for (i = 0; i <= 1000; i++) if (i in hist) { c += hist[i]; if (c * 2 >= n - 1) { med = i; break } }
  med /= 1000
  # Every closed pause becomes one usual interval.
  d = 0
  for (i = 0; i < n; i++) { if (i in RPGAP) d += med; RPT[i] += d }
  RPN = n; RPSPAN = n ? RPT[n - 1] + med : 1; RPI = 0; RPLAST = -1
}
# The answer for the time t: per field the peak of the lines recorded since the last call (as the agent holds a
# client's peaks); none since then: the last line with its bars and bass fallen 2.4 a second, the pulse 3.5 a
# second, no beat (the agent's own fall).
function replayLine(t,    got, i, k, rt, s, fall, v) {
  if (!RPN) return "unsupported" FLAT24
  got = 0
  while (1) {
    i = RPI % RPN; rt = RPT[i] + int(RPI / RPN) * RPSPAN
    if (rt > t) break
    if (!got) { RPST = RPS[i]; for (k = 1; k <= 24; k++) RPV[k] = RPF[i, k]; got = 1 }
    else for (k = 1; k <= 24; k++) if (RPF[i, k] > RPV[k]) RPV[k] = RPF[i, k]
    RPLAST = i; RPLASTT = rt; RPI++
  }
  if (!got) {
    if (RPLAST < 0) return "ok" FLAT24
    RPST = RPS[RPLAST]
    fall = 96 * (t - RPLASTT)
    for (k = 1; k <= 24; k++) { v = RPF[RPLAST, k]; if (k == 2 || k >= 5) v -= fall; else if (k == 3) v -= 140 * (t - RPLASTT); else if (k == 4) v = 0; RPV[k] = v > 0 ? int(v) : 0 }
  }
  s = RPST
  for (k = 1; k <= 24; k++) s = s " " RPV[k]
  return s
}

# MARK: Dump (budget and structure check)

function label() { return (!POWER ? "off" : tolower(ENAME[EFFECT]) (IDLE ? (SLEEPING ? " asleep" : " idle") : "") (COLUMN ? " +control" : "") (PORTRAIT ? " portrait" : "")) " 8x" GRID }
function seg(l) { if (!(l in SEGN)) { SEGN[l] = NSEG; SEGNAME[NSEG] = l; NSEG++ } return SEGN[l] }
function dumpTick(dt,    s, g, i) {
  s = seg(label())
  SSEC[s] += dt; SSAMP[s]++
  g = 0; for (i = 0; i < NKEY; i++) if (GLIDE[i] > NOW && i % NLV < GRID) g++
  SGSUM[s] += g; if (g > SGMAX[s]) SGMAX[s] = g
}
function signature(x) {
  gsub(/>[^<]*<\/text>/, ">T</text>", x)
  gsub(/#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])?/, "#", x)
  gsub(/-?[0-9]+(\.[0-9]+)?/, "#", x)
  return x
}
function dumpFrame(   s, i, f, n, sig, j) {
  FRAMENO++
  s = seg(label()); SFR[s]++
  j = "{\"t\":" NOW ",\"frame\":" FRAMENO ",\"effect\":\"" ENAME[EFFECT] "\",\"theme\":\"" TNAME[THEME] "\",\"power\":" (POWER ? "true" : "false")
  j = j ",\"control\":" (COLUMN ? "true" : "false") ",\"idle\":" (IDLE ? "true" : "false") ",\"asleep\":" (SLEEPING ? "true" : "false")
  j = j ",\"portrait\":" (PORTRAIT ? "true" : "false") ",\"grid\":" GRID ",\"levels\":["
  for (i = 0; i < 8; i++) j = j (i ? "," : "") n2(LV[i])
  # Dumps only, for the checks: the answer's levels before shaping (8 bands and the bass), the headroom H of each,
  # the shaped bass and the Bars heights before they are cut into steps.
  j = j "],\"bass\":" n2(BASS) ",\"raw\":["
  for (i = 0; i <= 8; i++) j = j (i ? "," : "") n2(RAWL[i])
  j = j "],\"head\":["
  for (i = 0; i <= 8; i++) j = j (i ? "," : "") n2(AGH[i])
  j = j "],\"bars\":["
  if (EFFECT == 0 && POWER && BARON) for (i = 0; i < 8; i++) j = j (i ? "," : "") n2(BARY[i])
  j = j "],\"lava\":["                         # each blob's radius (keys), flash and heat as drawn (Lava only)
  if (EFFECT == 2 && POWER) for (i = 0; i < 4; i++) j = j (i ? "," : "") "[" n2(LR[i] * LRS * (1 + LAVASWELL * LFL[i])) "," n2(LFL[i]) "," n2(0.45 + 0.2 * clamp((LR[i] - LAVAMIN) / LAVARANGE, 0, 1) + 0.35 * LFL[i]) "]"
  j = j "],\"curve\":["                        # the line's points as drawn (Curve only; for the checks)
  if (EFFECT == 3 && POWER) for (i = 0; i < 8; i++) j = j (i ? "," : "") CPY[i]
  j = j "],\"cells\":["
  for (i = 0; i < NKEY; i++) {
    # Compact: a key's SVG only when it changed (null: as in the frame before; "": the grid does not show the key).
    j = j (i ? "," : "") "{\"svg\":" (CHG[i] ? "\"" CUR[i] "\"" : CUR[i] == "" ? "\"\"" : "null") ",\"changed\":" (CHG[i] ? "true" : "false") ",\"near\":" (KNEAR[i] ? 1 : 0) ",\"duration\":" (CUR[i] == "" ? 0 : CURDUR[i]) "}"
    if (CHG[i]) {
      SUPD[s]++; n = length(CUR[i]); SBYTES[s] += n; if (n > SMAXB[s]) SMAXB[s] = n
      GLIDE[i] = NOW + CURDUR[i]
      sig = signature(CUR[i])
      if ((i in LASTSIG) && LASTSIG[i] != sig) { MIS++; if (MIS <= 20) MISL[MIS] = "frame " FRAMENO " cell " i " (band " int(i / NLV) ", level " i % NLV ") at " n2(NOW) " s" }
      LASTSIG[i] = sig
    }
  }
  f = sprintf("%s/f-%05d.json", DUMP, FRAMENO)
  print j "]}" > f; close(f)
}
function summary(   s, text, i) {
  text = "segment | seconds | frames/s | updates/s | gliding avg | gliding max | avg frame B | max frame B"
  for (s = 0; s < NSEG; s++) if (SSEC[s] > 0.05) text = text "\n" SEGNAME[s] " | " n1(SSEC[s]) " | " n1(SFR[s] / SSEC[s]) " | " n1(SUPD[s] / SSEC[s]) " | " n1(SGSUM[s] / (SSAMP[s] ? SSAMP[s] : 1)) " | " (SGMAX[s] + 0) " | " (SUPD[s] ? int(SBYTES[s] / SUPD[s]) : 0) " | " (SMAXB[s] + 0)
  text = text "\nstructure mismatches: " (MIS + 0)
  for (i = 1; i <= MIS && i <= 20; i++) text = text "\n" MISL[i]
  out(text)
  if (DUMP != "") { print text > (DUMP "/summary.txt"); close(DUMP "/summary.txt") }
}

$1 == "T" { if (NF == 35 || NF == 36) tick(); else out("N 0.25 1 0 0"); done(); next }
$1 == "S" { out(synthLine($2 + 0)); done(); next }
$1 == "P" { loadReplay(substr($0, 3)); out(RPN " " RPSPAN); done(); next }
$1 == "R" { out(replayLine($2 + 0)); done(); next }
$1 == "K" { delete LAST; FORCE = 1; done(); next }
$1 == "I" { for (i = 0; i < NKEY; i++) ID[i] = $(i + 2); done(); next }
$1 == "F" { faces(int($2), int($3), $4 == 4 ? 4 : 6); done(); next }
$1 == "X" { sample(); done(); next }
$1 == "B" { stage(eight(4), $3 != 0, $2 == 4 ? 4 : 6); if (NF >= 19) restage(eight(12)); for (i = 0; i < NKEY; i++) out(CUR[i] == "" ? "-" : CURDUR[i] " " CUR[i]); done(); next }
$1 == "D" { DUMP = $2; done(); next }
$1 == "V" { for (i = 0; i < NKEY; i++) out(CUR[i] == "" ? "-" : still(CUR[i], $2 == "c" ? "k" i : "")); done(); next }
$1 == "C" { for (i = 0; i < NKEY; i++) out(CUR[i] == "" ? "-" : CUR[i]); done(); next }
$1 == "Q" { summary(); done(); next }
{ done() }
AWK

integer aw_pid=0
aw_in="" aw_out=""
typeset -a aw_lines

aw_stop() {
  [[ -n $aw_in ]] && exec {aw_in}>&-            # awk ends at the end of its input
  [[ -n $aw_out ]] && exec {aw_out}<&-
  (( aw_pid )) && kill $aw_pid 2>/dev/null
  aw_in="" aw_out="" aw_pid=0
}

# Starts the renderer and tells it the page. It must not keep a copy of the agent connection.
aw_start() {
  aw_stop
  if [[ -n $sock ]]; then coproc /usr/bin/awk "$RENDER" {sock}>&-
  else coproc /usr/bin/awk "$RENDER"; fi
  aw_pid=$!
  exec {aw_out}<&p {aw_in}>&p
  aw_call "I $ids" || return 1
}

# aw_read <n>: exactly n bytes from the renderer into REPLY.
aw_read() {
  local chunk
  REPLY=""
  while (( ${#REPLY} < $1 )); do
    sysread -i $aw_out -s $(( $1 - ${#REPLY} )) -t 10 chunk || return 1
    REPLY+=$chunk
  done
}

# aw_call <command>: sends one command, collects the answer's records in aw_lines.
aw_call() {
  aw_lines=()
  print -r -u $aw_in -- "$1" 2>/dev/null || { log_once "the renderer is gone"; return 1 }
  while true; do
    aw_read 10 && [[ $REPLY == <-> ]] || { log_once "the renderer does not answer"; return 1 }
    (( 10#$REPLY )) || return 0
    aw_read $(( 10#$REPLY )) || { log_once "the renderer does not answer"; return 1 }
    aw_lines+=("$REPLY")
  done
}

# MARK: - Agent API: one keep-alive connection, HTTP/1.1 by hand

last_log=""
log_once() { [[ $1 == "$last_log" ]] && return; last_log=$1; print -u2 -r -- "visualizer: $1"; }

# flight: 1 while a request is being written, 2 while answers are awaited (inflight of them); rbuf: bytes read past
# the last answer (the next answers of a frame posted at once).
sock="" http_status=0 http_body="" api_fail="" rbuf=""
integer api_failures=0 auth_failures=0 flight=0 inflight=0 api_sent=0
typeset -F api_retry_at=0

api_close() { [[ -n $sock ]] && ztcp -c $sock 2>/dev/null; sock="" flight=0 inflight=0 rbuf=""; }

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

# read_answer <seconds>: one whole answer from the connection into http_status / http_body; 1 when the connection
# closed first or the answer cannot be read (a length that is not a number), 2 when nothing came in time. What came
# after the answer (the next answers of a frame posted at once) stays in rbuf for the next call.
read_answer() {
  local buf=$rbuf chunk head header length
  local -a found
  integer len=0
  rbuf=""
  while [[ $buf != *$'\r\n\r\n'* ]]; do
    sysread -i $sock -t $1 chunk || { (( $? == 4 )) && return 2; return 1 }
    buf+=$chunk
  done
  # Cut by length, not by ${buf#*…}: zsh matches a shortest prefix by trying every length, which cost 50 µs an
  # answer — at 200 posts a second, most of the loop's time.
  head=${buf%%$'\r\n\r\n'*}
  header=${(L)head} http_body=${buf:$(( ${#head} + 4 ))}
  found=(${(M)${(f)header}:#content-length:*})
  if (( $#found )); then
    # Checked before it is a number: whatever else answers on this port must not stop the loop.
    length=${${found[1]#content-length:}//[[:space:]]/}
    [[ $length == <-> && ${#length} -le 9 ]] || { log_once "an answer with a length that is not a number"; return 1 }
    len=$length
  fi
  while (( ${#http_body} < len )); do
    sysread -i $sock -t $1 chunk || return 1
    http_body+=$chunk
  done
  (( $#found && ${#http_body} > len )) && rbuf=${http_body:$len} http_body=${http_body:0:$len}
  http_status=${${header#* }%% *}
  [[ $http_status == <-> ]] || http_status=0
  [[ $header == *$'\n'connection:\ close* ]] && api_close
  return 0
}

# api METHOD TARGET [BODY] [seconds] [tries]: sets http_status and http_body; 1 when no answer came. A request on a
# kept connection the agent had closed is tried once more on a new one (tries: 2 unless given). api_sent: the
# requests that went out (the levels limit below counts each against its 16 a second); api_fail: why it failed (closed,
# timeout, connect).
api() {
  local method=$1 target=$2 body=$3 request
  integer try tries=${5:-2}
  http_status=0 http_body="" api_sent=0 api_fail=""
  (( dry )) && return 1                         # the dry modes never open a connection
  for (( try = 1; try <= tries; try++ )); do
    [[ -n $sock ]] || api_connect || { api_fail=connect; return 1 }
    request="$method $target HTTP/1.1"$'\r\n'"Host: 127.0.0.1"$'\r\n'"Authorization: Bearer $token"$'\r\n'
    [[ -n $body ]] && request+="Content-Type: application/json"$'\r\n'"Content-Length: ${#body}"$'\r\n'
    flight=1
    if ! print -rn -u $sock -- "$request"$'\r\n'"$body" 2>/dev/null; then api_close; api_fail=closed; continue; fi
    flight=2 inflight=1 api_sent+=1
    read_answer ${4:-2}
    case $? in
      0) ;;
      1) api_close; api_fail=closed; continue ;;   # a keep-alive connection the agent had closed: once more on a new one
      *) api_close; api_fail=timeout; log_once "the agent did not answer $target in time"; return 1 ;;
    esac
    flight=0 inflight=0
    if (( http_status == 401 )); then
      # A stale token never heals by itself: the agent restarts the script with a fresh one.
      (( ++auth_failures >= 3 )) && { print -u2 "visualizer: the agent does not accept DESMAPTIC_TOKEN"; exit 4; }
    else
      auth_failures=0
    fi
    return 0
  done
  return 1
}

# MARK: - Is the page on the phone's screen, which way up, and which grid?

integer shown=0 levels_allowed=0 unknown_views=0 orient=0 orient_changed=0 grid=4 grid_changed=0
typeset -F view_at=-100 view_next=0
typeset -A cell_index drawn_ids

# shown = the phone shows this page: its own button ({{CELL_ID}}) is among the view's cells. Levels are asked for only
# once the page has been seen: the first request makes macOS ask for the recording permission. orient: 1 in portrait.
# grid: 6 when the phone lists one of the page's iPad keys (levels 4 and 5: an iPad), otherwise 4. A phone app or an
# agent too old to list the cells shows nothing: the keys cannot be found.
view_check() {
  local seen list obj id gi keys part op cl sep='},{'
  local -a found
  integer o g i row col me d
  view_at=$SECONDS
  (( dry )) && { shown=1 levels_allowed=1; return 0 }
  api GET /api/view "" 2 || return 1
  case $http_status in
    404) shown=0; log_once "this agent cannot say where the keys are (no /api/view)" ;;
    200)
      shown=0 seen=${(U)http_body// /}
      [[ $seen == *'"CONNECTED":TRUE'* ]] || return 0
      # An iPad shows several windows side by side, each on its own page, and the top-level fields are only the
      # window touched last; "windows" lists every one (that one first) with its own cells and grid. Read the one
      # that holds this button; none does (an older app, none yet): the top-level fields, without the windows.
      if [[ $seen == *'"WINDOWS":['* ]]; then
        list=$seen obj="" d=0
        seen=${seen%%'"WINDOWS":['*}             # cut by length: ${seen#*…} is slow this far into the body
        list=${list:$(( ${#seen} + 11 ))}
        for part in "${(@ps:$sep:)list}"; do
          obj+=${obj:+$sep}$part
          op=${part//[^\{\[]/} cl=${part//[^\}\]]/}
          (( d += ${#op} - ${#cl} ))
          (( d > 1 )) && continue
          [[ $obj == *\"$client_id\"* ]] && { seen=$obj; break }
          obj="" d=1                               # the split took the next window's "{"
        done
      fi
      list=${seen#*'"CELLS":['}
      if [[ $list == $seen ]]; then log_once "the phone app is too old to say where the keys are"; return 0; fi
      list=${list%%\]*}
      for (( i = 1; i <= 48; i++ )); do found[i]=-; done
      g=4 me=0
      list=${list//"},{"/$'\n'}                  # one cell a line
      for obj in ${(f)list}; do
        gi=${obj#*'"GALLERYITEM":"'}
        [[ $gi != $obj ]] || continue
        gi=${gi%%\"*}
        [[ $gi == VISUALIZER.R<0-7>C<0-5> && $obj == *'"ID":"'* && $obj == *'"ROW":'<->* && $obj == *'"COL":'<->* ]] || continue
        id=${${obj#*'"ID":"'}%%\"*}
        row=${${obj#*'"ROW":'}%%[^0-9]*} col=${${obj#*'"COL":'}%%[^0-9]*}
        (( row <= 7 && col <= 5 )) || continue
        (( i = row * 6 + col + 1 ))
        found[i]=$id
        (( col >= 4 )) && g=6
        [[ $id == $client_id ]] && me=1
      done
      (( me )) || return 0
      shown=1 levels_allowed=1
      [[ $seen == *('"ORIENTATION":"PORTRAIT"'|'"ISLANDSCAPE":FALSE')* ]] && o=1 || o=0
      (( o != orient )) && orient=$o orient_changed=1
      (( g != grid )) && grid=$g grid_changed=1
      keys=${(j: :)found}
      [[ $keys == $ids ]] || set_keys $keys ;;
    *) return 1 ;;
  esac
  return 0
}

go_hidden() { shown=0 view_next=$(( SECONDS + 1 )); log_once "resting: $1"; }

# MARK: - Levels

integer lv_audible=0 lv_bass=0 lv_pulse=0 lv_beat=0 lv_fresh=0 lv_closed=0
FLAT="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"
lv_bands=$FLAT lv_state=none lv_synth=S
typeset -F lv_asked_at=-100 lv_next_at=0
typeset -a lv_times                             # when the last 16 requests went out

levels_flat() { lv_audible=0 lv_bass=0 lv_pulse=0 lv_beat=0 lv_bands=$FLAT; }

# levels_parse <line>: the agent's answer `<state> <audible> <bass> <pulse> <beat> <l0> … <l19>`; 1 (and flat
# levels) for anything but a whole "ok" line of small numbers — starting, error, unsupported, or a line this
# script does not know.
levels_parse() {
  setopt localoptions extendedglob
  local -a f
  f=(${=1})
  lv_state=${f[1]:-empty}
  if [[ $#f == 25 && $f[1] == ok && ${(j: :)f[2,25]} == ([0-9](#c1,3) )(#c23)[0-9](#c1,3) ]]; then
    lv_audible=$f[2] lv_bass=$f[3] lv_pulse=$f[4] lv_beat=$f[5] lv_bands="${f[6,25]}"
    return 0
  fi
  levels_flat
  return 1
}

# poll_levels <now> <gap>: at most 16 in any second and not within <gap> seconds of the last one, only while the page
# is on screen and the visualizer is on; 404 = an agent without this route: flat bands, asked again once a minute;
# anything else that is not "ok": flat, asked again in a second. lv_fresh = 1 when it asked (the levels are news
# for the renderer). 2 when the 16-per-second limit refused the request (the caller may wait for it instead).
poll_levels() {
  local -F now=$1
  integer tries=1
  (( now - lv_asked_at >= $2 && now >= lv_next_at )) || return 0
  (( $#lv_times < 16 || now - lv_times[1] >= 1.02 )) || return 2
  lv_asked_at=$now lv_fresh=1
  lv_times+=($now); (( $#lv_times > 16 )) && shift lv_times
  if (( dry )); then
    aw_call "$lv_synth $now" && levels_parse "$aw_lines[1]"
    return 0
  fi
  # A second try on a new connection (the agent had closed the kept one) is a request too: only while it keeps the
  # 16 in any second. Without it the levels stay as they were and the next request (on a new connection) goes out as
  # soon as the limit allows; a second failure in a row is a failure (flat, asked again in a second).
  (( $#lv_times < 16 || now - lv_times[1] >= 1.02 )) && tries=2
  if ! api GET "/api/audio/levels?client=$client" "" 1 $tries; then
    (( api_sent > 1 )) && { lv_times+=($SECONDS); (( $#lv_times > 16 )) && shift lv_times }
    [[ $api_fail == closed ]] && (( tries == 1 && lv_closed++ == 0 )) && { lv_fresh=0; return 0 }
    levels_flat; lv_next_at=$(( now + 1 )) lv_closed=0
    return 0
  fi
  (( api_sent > 1 )) && { lv_times+=($SECONDS); (( $#lv_times > 16 )) && shift lv_times }
  lv_closed=0
  case $http_status in
    200) levels_parse "$http_body" || { lv_next_at=$(( now + 1 )); log_once "levels: $lv_state" } ;;
    404) levels_flat; lv_next_at=$(( now + 60 )); log_once "this agent has no /api/audio/levels: flat bands" ;;
    *) levels_flat; lv_next_at=$(( now + 1 )); log_once "levels: HTTP $http_status" ;;
  esac
  return 0
}

# MARK: - Controls: taps, effect, theme, power

integer effect=0 theme=0 power=1 tapped=0 switched=0 new_tap=0
typeset -F control_until=-1 behind_until=-100
last_tap="" tap_waiting="" store=""
typeset -F tap_wait_until=0

read_int() { local v=""; [[ -r $1 ]] && read -r v < $1; [[ $v == <-> && ${#v} -le 6 ]] && REPLY=$v || REPLY=$2; }

save_state() {
  [[ -n $store ]] || return 0
  local name value
  for name value in k-effect $effect k-theme $theme k-power $power; do
    { print -r -- $value > $store/$name.$$ && zf_mv -f $store/$name.$$ $store/$name } 2>/dev/null || log_once "cannot save $name"
  done
}

# tap <index> <now>: the control column appears for 4 s; on it (band 7), power at the top, the effect and the theme
# under it, the logo key at the bottom — the same parts the renderer draws (rolePart): power on level grid-1, the
# effect on grid-2, the theme on grid-3.
tap() {
  integer band=$(( $1 / 6 )) level=$(( $1 % 6 )) fresh=0
  local -F now=$2
  tapped=1
  # A tap on one of the iPad's keys: the phone shows them, whatever the last look said. From now on the picture is
  # drawn for that grid; this tap only opens the column (the key did not show a control).
  (( level >= grid )) && grid=6 grid_changed=1 fresh=1
  if (( ! power )); then
    power=1 switched=1 control_until=$(( now + 4 ))
    save_state; return
  fi
  if (( fresh || now >= control_until || band != 7 )); then control_until=$(( now + 4 )); return; fi
  if (( level == grid - 1 )); then power=0 switched=1 control_until=-1; save_state; return
  elif (( level == grid - 2 )); then (( effect = (effect + 1) % 4 )); switched=1; save_state
  elif (( level == grid - 3 )); then (( theme = (theme + 1) % 9 )); switched=1; save_state
  fi
  control_until=$(( now + 4 ))
}

# The buttons write "<id> <time>" to k-tap; a line not seen before is a new tap. The file holds one tap, so two
# within one look at it (83 ms while shown) count as one. A key the loop does not know yet — the page has just
# opened, and the phone's word of it may reach the agent a moment after the tap — keeps the screen looked at on every
# pass for up to 2 s, and the tap is taken as soon as a look lists the key; still unknown then (a key of another
# page), it is dropped.
poll_tap() {
  [[ -n $store && -r $store/k-tap ]] || return 0
  local line="" id
  read -r line < $store/k-tap
  [[ -n $line && $line != $last_tap ]] || return 0
  id=${(U)line%% *}
  if (( ! $+cell_index[$id] )); then
    [[ $line == $tap_waiting ]] || tap_waiting=$line tap_wait_until=$(( $1 + 2 ))
    (( $1 < tap_wait_until )) && { new_tap=1; return 0 }
  fi
  last_tap=$line
  (( $+cell_index[$id] )) && { tap $cell_index[$id] $1; new_tap=1 }
  return 0
}

# MARK: - A tick: levels → renderer → frames

integer frames=0 posts=0 post_failures=0 tick_idle=0 tick_asleep=0
typeset -F tick_iv=0.25 tick_defer=0

# levels_for_tick <now>: the levels for this tick. Bars with music draw twice as often as they ask (every 1/22 s,
# a request at most every 0.08 s: 11 a second) and Lava asks between its frames (it listens for the beat); for both,
# a frame without new levels still moves. Amoeba and Curve ask on every frame. 2: wait for the 16-per-second limit
# (tick_defer, a hair after it: the sum must not come out just under it) before drawing.
levels_for_tick() {
  lv_fresh=0
  (( power && levels_allowed )) || return 0
  if (( (effect == 0 || effect == 2) && ! tick_idle )); then poll_levels $1 0.08; return 0; fi
  poll_levels $1 0.05
  # A frame from the same levels again would stand still: wait until the limit lets the request out. Taps and
  # switches are drawn at once.
  if (( $? == 2 )) && (( ! tapped && ! switched )); then tick_defer=$(( lv_times[1] + 1.021 )); return 2; fi
  return 0
}

# post_seen <body>: what the agent said about one key's frame (http_status, http_body). 0: go on; 1: stop — the
# reason is in post_stop (off: the page or that key is off the phone's screen; nophone; error).
post_stop="" post_stop_key=""
post_seen() {
  local answer
  case $http_status in
    200)
      posts+=1 answer=${http_body// /}
      [[ $answer == *'"dropped":true'* ]] && behind_until=$(( SECONDS + 2 ))   # the phone is not reading: slow down
      [[ $answer == *'"visible":false'* ]] && { post_stop=off post_stop_key=${${1#*'"cellId":"'}%%\"*}; return 1 } ;;
    503) post_stop=nophone; return 1 ;;
    400) log_once "update-button 400: ${http_body[1,300]}" ;;
    *) post_stop=error; log_once "update-button HTTP $http_status"; return 1 ;;
  esac
  return 0
}

# post_frame: the frame's update-button bodies (aw_lines[2..]). The first goes alone: its answer says whether the page
# (and, on the iPad's grid, its own levels 4 and 5: the renderer puts one of those first) is still on the phone's
# screen, so a page that left gets one post, not a frame's worth. The rest are written at once and their answers read
# in order: HTTP/1.1 pipelining — the agent reads them one after another from the connection and answers each in
# turn, so the keys of one frame reach the phone as close together as the agent can send them (one answer before
# the next request spread a frame of 20 keys over 20 round trips). After a reason to stop, the rest of the answers
# are only read. An answer that closes the connection (an agent that does not keep it) leaves the requests after it
# unread by the agent: those go again on a new connection, unless the frame stops. No request goes twice once the
# agent may have read it. 1: stop and rest (post_stop says why; fail: no answer).
post_frame() {
  local all body
  integer i n=$#aw_lines from=3 rc
  post_stop="" post_stop_key=""
  api POST /api/update-button "$aw_lines[2]" 2 || { post_stop=fail; return 1 }
  post_seen "$aw_lines[2]" || return 1
  while (( from <= n )); do
    [[ -n $sock ]] || api_connect || { post_stop=fail; return 1 }
    all=""
    for (( i = from; i <= n; i++ )); do
      body=$aw_lines[i]
      all+="POST /api/update-button HTTP/1.1"$'\r\n'"Host: 127.0.0.1"$'\r\n'"Authorization: Bearer $token"$'\r\n'"Content-Type: application/json"$'\r\n'"Content-Length: ${#body}"$'\r\n\r\n'"$body"
    done
    flight=1
    print -rn -u $sock -- "$all" 2>/dev/null || { api_close; post_stop=fail; return 1 }
    flight=2 inflight=$(( n - from + 1 ))
    for (( i = from; i <= n; i++ )); do
      read_answer 2; rc=$?
      if (( rc )); then
        api_close; post_stop=fail
        (( rc == 2 )) && log_once "the agent did not answer a frame in time"
        return 1
      fi
      (( inflight-- ))
      if (( http_status == 401 )); then
        # A stale token never heals by itself: the agent restarts the script with a fresh one.
        (( ++auth_failures >= 3 )) && { print -u2 "visualizer: the agent does not accept DESMAPTIC_TOKEN"; exit 4; }
      else
        auth_failures=0
      fi
      [[ -n $post_stop ]] || post_seen "$aw_lines[i]"
      if [[ -z $sock ]]; then
        [[ -n $post_stop ]] && return 1
        from=$(( i + 1 )); continue 2              # the agent closed it after this answer: the rest again
      fi
    done
    flight=0
    [[ -z $post_stop ]]
    return
  done
  return 0
}

tick() {
  local -F now=$1
  integer col beh i n
  local id
  levels_for_tick $now || return
  (( col = power && now < control_until, beh = now < behind_until ))
  aw_call "T $now $effect $theme $power $col $switched $tapped $beh $orient $grid $lv_audible $lv_bass $lv_pulse $lv_beat $lv_bands $lv_fresh" || { aw_restart; return }
  tapped=0 switched=0 lv_beat=0               # a beat counts once
  local -a head
  head=(${=aw_lines[1]})
  tick_iv=${head[2]:-0.25}
  tick_idle=${head[3]:-0} tick_asleep=${head[5]:-0}
  n=$#aw_lines
  (( head[4] )) && frames+=1
  (( dry )) && { posts+=$(( n - 1 )); return }
  (( n >= 2 )) || return
  post_frame && return
  case $post_stop in
    # No answer: the agent restarts or is gone. Rest until it answers again, then send every key again.
    fail) post_failures+=1 need_key=1; go_hidden "the agent does not answer" ;;
    off)
      go_hidden "the page is off screen"; need_key=1
      # One of the iPad's keys is not on screen: the phone may show only the phone's grid now. Look at once.
      (( ${cell_index[$post_stop_key]:-0} % 6 >= 4 )) && view_next=$SECONDS ;;
    nophone) go_hidden "no phone connected"; need_key=1 ;;
    *) post_failures+=1 need_key=1 ;;
  esac
}

integer need_key=0 aw_restarts=0
typeset -F aw_restart_at=0
aw_restart() {
  (( SECONDS >= aw_restart_at )) || return
  aw_restart_at=$(( SECONDS + 2 ))
  (( ++aw_restarts > 20 )) && { print -u2 "visualizer: the renderer keeps failing"; exit 3; }
  log_once "restarting the renderer"
  aw_start && need_key=1
}

# MARK: - Stop: every key back to its saved face

# Stopped by the agent (disconnect, profile switch, restart): the resets go out on the same connection after any
# request already on it, so no frame lands after its key's reset; then out within a second. A single request still
# owed an answer (levels, a look, a frame's first key) is waited for 0.25 s: one that hangs gets its connection closed,
# and the resets go on a new one. A frame's keys posted at once never hang on their own: the resets queue behind them
# and the loop waits for all the answers (one fewer once nothing more comes for 50 ms: the signal may have landed in
# the middle of reading an answer).
on_term() {
  trap '' TERM INT HUP
  local all="" id buf="" chunk body
  local -a answers
  local -F deadline=$(( SECONDS + 0.8 )) wait
  integer owed=0 need resets=0
  if (( ! dry )); then
    if (( flight == 1 )); then api_close
    elif (( flight == 2 && inflight == 1 )) && [[ -n $sock ]]; then read_answer 0.25 || api_close
    elif (( flight == 2 && inflight > 1 )) && [[ -n $sock ]]; then owed=$inflight
    fi
    api_retry_at=0
    if [[ -n $sock ]] || api_connect; then
      for id in ${(k)drawn_ids}; do
        (( resets++ ))
        body="{\"cellId\":\"$id\",\"reset\":true}"
        all+="POST /api/update-button HTTP/1.1"$'\r\n'"Host: 127.0.0.1"$'\r\n'"Authorization: Bearer $token"$'\r\n'"Content-Type: application/json"$'\r\n'"Content-Length: ${#body}"$'\r\n\r\n'"$body"
      done
      if print -rn -u $sock -- "$all" 2>/dev/null; then
        # Wait for the answers: the resets (every key the phone listed on this run, the iPad's too: a reset of a key
        # the phone does not show changes nothing) and those still owed, or the deadline.
        buf=$rbuf need=$(( resets + owed ))
        answers=("${(@s:HTTP/1.1 :)buf}")
        while (( SECONDS < deadline && $#answers <= need )); do
          wait=$(( deadline - SECONDS ))
          (( owed && $#answers >= need && wait > 0.05 )) && wait=0.05
          sysread -i $sock -t $wait chunk || break
          buf+=$chunk
          answers=("${(@s:HTTP/1.1 :)buf}")
        done
      fi
    fi
  fi
  aw_stop
  exit 0
}

# MARK: - Start

usage() { print -u2 -- "usage: engine.zsh [--faces out.json | --cover out.svg | --dump <4|6> <portrait|landscape> <HH:MM> <step> out.json | --bars <4|6> <portrait|landscape> <h0,…,h7>[:<h0,…,h7>] out.json]"; exit 2; }
tool="" tool_out=""
if (( $# )); then
  case $1 in
    --faces|--cover) (( $# == 2 )) || usage; tool=${1#--} tool_out=$2 ;;
    --dump)
      (( $# == 6 )) && [[ $2 == (4|6) && $3 == (portrait|landscape) && $4 == <->:<-> && $5 == <-> ]] || usage
      tool=dump tool_out=$6 tool_grid=$2 tool_steps=$5
      [[ $3 == portrait ]] && tool_orient=1 || tool_orient=0 ;;
    --bars)
      (( $# == 5 )) && [[ $2 == (4|6) && $3 == (portrait|landscape) ]] || usage
      tool_heights=(${(s:,:)${4%%:*}}) tool_next=()
      [[ $4 == *:* ]] && tool_next=(${(s:,:)${4#*:}})
      (( $#tool_heights == 8 && ($#tool_next == 0 || $#tool_next == 8) )) || usage
      for tool_h in $tool_heights $tool_next; do [[ $tool_h == <->(|.<->) ]] || usage; done
      tool=bars tool_out=$5 tool_grid=$2
      [[ $3 == portrait ]] && tool_orient=1 || tool_orient=0 ;;
    *) usage ;;
  esac
fi

integer dry=0
[[ -n $tool || ${VIS_DRY:-} == 1 || -n ${VIS_DUMP:-} || -n ${VIS_FACES:-} ]] && dry=1

page_cells
ids="$reply" page_ids=($reply)
integer i
for (( i = 1; i <= 48; i++ )); do [[ $reply[i] == - ]] || cell_index[$reply[i]]=$(( i - 1 )); done

if (( dry )); then
  store=${VIS_STORAGE:-}
  effect=${VIS_EFFECT:-0} theme=${VIS_THEME:-0} power=${VIS_POWER:-1}
  [[ ${VIS_ORIENT:-} == portrait ]] && orient=1
  [[ ${VIS_GRID:-} == 6 ]] && grid=6
else
  # Posting needs the agent's run: its token comes only with a script the agent started.
  if [[ -z $token || -z ${DESMAPTIC_STORAGE:-} ]]; then
    print -u2 "visualizer: not started by Desmaptic Agent (no DESMAPTIC_TOKEN / DESMAPTIC_STORAGE): try VIS_DRY=1 or VIS_DUMP=<folder>"
    exit 2
  fi
  store=$DESMAPTIC_STORAGE/gallery/visualizer
fi
if [[ -n $store ]]; then
  zf_mkdir -p $store 2>/dev/null || log_once "cannot make $store"
  read_int $store/k-effect $effect; effect=$(( REPLY % 4 ))
  read_int $store/k-theme $theme; theme=$(( REPLY % 9 ))
  read_int $store/k-power $power; power=$(( REPLY != 0 ))
  [[ -r $store/k-tap ]] && read -r last_tap < $store/k-tap      # a tap from before this start is not a new one
fi
(( effect = effect % 4, theme = theme % 9, power = power != 0 ))

aw_start || { print -u2 "visualizer: the renderer (awk) does not start"; exit 3; }
trap 'on_term' TERM INT HUP
if (( dry )) && [[ -n ${VIS_REPLAY:-} ]]; then
  [[ -r $VIS_REPLAY ]] && aw_call "P $VIS_REPLAY" && [[ ${aw_lines[1]%% *} != 0 ]] || { print -u2 "visualizer: no answers in $VIS_REPLAY"; exit 2; }
  lv_synth=R
fi

if [[ -n ${VIS_FACES:-} ]]; then
  aw_call "F 0 0 6" && (( $#aw_lines == 48 )) || { print -u2 "visualizer: no faces"; exit 3; }
  { print -rn -- '{"cellIds":["'${(j:",":)reply}'"],"faces":["'${(j:",":)aw_lines}'"]}'; print } > $VIS_FACES
  aw_stop; exit 0
fi

if [[ -n $tool ]]; then
  # Synthetic music on a virtual clock (as the dump runs it) for <seconds>, with <effect> <portrait> <grid>.
  tool_run() {
    local -F t=0 end=$1
    local -a head
    effect=$2 orient=$3 grid=$4 theme=0 power=1 shown=1 levels_allowed=1
    while (( t < end )); do
      if ! levels_for_tick $t; then t=$tick_defer tick_defer=0; continue; fi
      aw_call "T $t $effect $theme $power 0 0 0 0 $orient $grid $lv_audible $lv_bass $lv_pulse $lv_beat $lv_bands $lv_fresh" || exit 3
      lv_beat=0 head=(${=aw_lines[1]})
      tick_idle=${head[3]:-0}
      (( t += head[2] > 0 ? head[2] : 0.25 ))
    done
  }
  local -a demo rest
  local svg k
  integer n=0
  case $tool in
    faces)
      # the sample: a still of the live Bars at a staged moment, which reads upright and turned (the renderer's X);
      # the resting face: the calm idle look the page is saved with
      aw_call X && (( $#aw_lines == 48 )) || exit 3
      demo=("${aw_lines[@]}")
      aw_call "F 0 0 6" && aw_call V && (( $#aw_lines == 48 )) || exit 3
      rest=("${aw_lines[@]}")
      {
        print -rn -- "{"
        for (( i = 1; i <= 48; i++ )); do
          (( i > 1 )) && print -rn -- ","
          print -rn -- "\"r$(( (i - 1) / 6 ))c$(( (i - 1) % 6 ))\":{\"rest\":\"$rest[i]\",\"demo\":\"$demo[i]\"}"
        done
        print "}"
      } > $tool_out || exit 2 ;;
    cover)
      # Bars on the iPhone's grid in landscape: the 32 keys as one picture, the gaps between them drawn over it
      tool_run 12 0 0 4
      aw_call "V c" && (( $#aw_lines == 48 )) || exit 3
      svg="<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 800 400'>"
      for (( i = 1; i <= 48; i++ )); do
        [[ $aw_lines[i] == - ]] && continue
        k=${aw_lines[i]#*>}; svg+=${k%</svg>}
      done
      svg+="<path d='M100 0V400M200 0V400M300 0V400M400 0V400M500 0V400M600 0V400M700 0V400M0 100H800M0 200H800M0 300H800' fill='none' stroke='#05060C' stroke-width='6'/></svg>"
      print -r -- $svg > $tool_out || exit 2 ;;
    dump|bars)
      if [[ $tool == dump ]]; then
        tool_run $(( tool_steps / 10.0 )) 0 $tool_orient $tool_grid
        aw_call C
      else
        aw_call "B $tool_grid $tool_orient $tool_heights $tool_next"
      fi && (( $#aw_lines == 48 )) || exit 3
      {
        print -rn -- "["
        for (( i = 1; i <= 48; i++ )); do
          [[ $aw_lines[i] == - ]] && continue
          (( n++ )) && print -rn -- ","
          svg=$aw_lines[i] k=""
          [[ $tool == bars ]] && k=",\"duration\":${svg%% *}" svg=${svg#* }
          print -rn -- "{\"row\":$(( (i - 1) / 6 )),\"col\":$(( (i - 1) % 6 ))$k,\"svg\":\"$svg\"}"
        done
        print "]"
      } > $tool_out || exit 2 ;;
  esac
  aw_stop; exit 0
fi

if [[ -n ${VIS_DUMP:-} ]]; then
  # A virtual clock, as fast as it runs; events from VIS_EVENTS="t:tap:band:level,t:orient:portrait,t:grid:6,
  # t:music:0,t:key,…"; nothing is posted.
  zf_mkdir -p $VIS_DUMP || exit 2
  aw_call "D $VIS_DUMP"
  local -a events ev
  local item at
  integer music=$(( ${VIS_MUSIC:-1} != 0 ))
  for item in ${(s:,:)${VIS_EVENTS:-}}; do
    ev=(${(s.:.)item})
    [[ $ev[1] == <->(|.<->) ]] || continue
    printf -v at '%012.4f' $ev[1]                   # sorts as text in time order
    case $ev[2] in
      tap) [[ $#ev == 4 && $ev[3] == <0-7> && $ev[4] == <0-5> ]] && events+=("$at tap $(( ev[3] * 6 + ev[4] ))") ;;
      orient) [[ $ev[3] == (portrait|landscape) ]] && events+=("$at orient $ev[3]") ;;
      grid) [[ $ev[3] == (4|6) ]] && events+=("$at grid $ev[3]") ;;
      music) [[ $ev[3] == <0-1> ]] && events+=("$at music $ev[3]") ;;
      key) events+=("$at key") ;;
      effect) [[ $ev[3] == <0-3> ]] && events+=("$at effect $ev[3]") ;;
    esac
  done
  events=(${(o)events})
  local -F t=0 end=${VIS_SECONDS:-50} et
  shown=1 levels_allowed=1
  while (( t < end )); do
    while (( $#events )); do
      ev=(${=events[1]})
      (( ev[1] <= t )) || break
      case $ev[2] in
        tap) tap $ev[3] $ev[1] ;;
        orient) [[ $ev[3] == portrait ]] && orient=1 || orient=0 ;;
        grid) grid=$ev[3] ;;
        music) music=$ev[3] ;;
        key) aw_call K ;;                         # the loop's keyframe: every key sent again
        effect) effect=$ev[3] switched=1 ;;       # any switch, not only the next effect a tap gives
      esac
      events[1]=()
    done
    # The levels as the loop asks for them (the same spacing and limit), from the synthetic music or the recording.
    if ! levels_for_tick $t; then t=$tick_defer tick_defer=0; continue; fi
    (( music )) || levels_flat
    (( col = power && t < control_until ))
    aw_call "T $t $effect $theme $power $col $switched $tapped 0 $orient $grid $lv_audible $lv_bass $lv_pulse $lv_beat $lv_bands $lv_fresh" || exit 3
    tapped=0 switched=0 lv_beat=0
    local -a head; head=(${=aw_lines[1]})
    tick_idle=${head[3]:-0}
    local -F step=$(( head[2] > 0 ? head[2] : 0.25 ))
    # The next event and the control column's end come on time, not a long step late.
    (( $#events )) && et=${events[1]%% *} && (( et > t && et < t + step )) && step=$(( et - t ))
    (( control_until > t && control_until < t + step )) && step=$(( control_until - t ))
    (( t += step ))
  done
  aw_call "Q" && print -rl -- $aw_lines
  aw_stop; exit 0
fi

# MARK: - The loop

typeset -F now tick_at=-1 key_at=0 wake stats_at=0
integer cs col_was=0
(( dry )) && stats_at=$(( SECONDS + 2 ))
# Until the phone says otherwise, the page counts as off screen: not even one levels request before that.
while true; do
  now=$SECONDS
  poll_tap $now
  if (( ! shown )); then
    if (( new_tap || now >= view_next )); then       # a tap means somebody looks at the page: look at once
      new_tap=0 view_next=$(( now + 1 ))
      if view_check; then
        if (( shown )); then
          log_once "on screen"
          need_key=1 tick_at=$now orient_changed=0 grid_changed=0
        fi
      else
        (( api_retry_at > view_next )) && view_next=$api_retry_at
      fi
    fi
  fi
  if (( shown )); then
    (( tapped )) && tick_at=$now new_tap=0
    (( col_was && now >= control_until )) && tick_at=$now          # the control column times out
    (( orient_changed )) && tick_at=$now orient_changed=0         # the phone turned
    (( grid_changed )) && tick_at=$now grid_changed=0             # the other grid: the renderer resends every key
    (( now - key_at >= 30 )) && { need_key=1; tick_at=$now }       # the face can be cleared from outside
    if (( need_key )); then
      aw_call K && need_key=0 key_at=$now
      tick_at=$now
    fi
    if (( tick_at >= 0 && now >= tick_at )); then
      tick $now
      (( col_was = power && now < control_until ))
      if (( tick_defer > 0 )); then
        tick_at=$tick_defer tick_defer=0
      elif (( tick_iv > 0 )); then
        (( tick_at += tick_iv ))
        (( tick_at < SECONDS )) && tick_at=$SECONDS
      else
        tick_at=-1                              # off: a dark deck that stands still, drawn again on a tap
      fi
    fi
    # A look at the phone's screen every second while the page is shown: which way up, and whether it is still
    # there while nothing is sent (silence, off).
    if (( shown && SECONDS - view_at >= 1 )); then
      view_check && (( ! shown )) && go_hidden "the page is off screen"
    fi
  fi
  if (( dry && SECONDS >= stats_at )); then
    print -u2 "visualizer (dry): frames/s=$(( frames / 2.0 )) updates/s=$(( posts / 2.0 )) effect=$effect theme=$theme power=$power idle=$tick_idle asleep=$tick_asleep"
    frames=0 posts=0 stats_at=$(( SECONDS + 2 ))
  fi
  # Sleep until the next thing to do: a tick, a look at the screen, or the next look at the tap file.
  (( wake = SECONDS + (shown ? 0.083 : 0.25) ))
  (( shown && tick_at >= 0 && tick_at < wake )) && wake=$tick_at
  (( shown && view_at + 1 < wake )) && wake=$(( view_at + 1 ))
  (( ! shown && view_next < wake )) && wake=$view_next
  (( shown && col_was && control_until < wake )) && wake=$control_until
  (( cs = (wake - SECONDS) * 100 + 0.5 ))
  (( cs > 0 )) && zselect -t $cs
done