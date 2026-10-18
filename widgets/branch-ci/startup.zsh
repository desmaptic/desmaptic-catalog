# Branch CI: the GitHub Actions CI of a branch's latest commit on a 2×1 SVG face — ✓ passed, ✗ failed, ● running, the
# workflow's name and how long ago it ran (1×2 turned: the mark on top, the words under it). The startup script is the
# settings, common.zsh and then this file (item.json).
#
# The runs are the branch's push and pull request runs (the Actions API through gh): once a minute, and only while the
# button is on screen; off screen nothing is asked, only a look at the phone every 5 s. The face shows the worst run of
# the latest commit (ci_pick). What the loop saw goes to gallery/{{CELL_ID}}/run (the run's id, address and
# result): the tap opens it and the long press reruns its failed jobs (open.zsh, rerun.zsh). Those leave
# gallery/{{CELL_ID}}/poke to have the face drawn again at once, and the long press gallery/{{CELL_ID}}/hold — "armed
# <time>" while it waits 10 s for the second press, "rerun <time>" once it asked GitHub — which the loop shows.
#
# Without gh, signed out, without a repository or with no run on the branch, the mark is a grey "—", the phone says why
# (/api/error) and gallery/{{CELL_ID}}/problem keeps it for the tap. A passing hitch (no network, GitHub slow or out of
# questions) keeps the last run, its reason to the phone; after 15 minutes without an answer it turns grey as well, so
# an old result never passes for a current one. The log gets the reason, never a repository, folder or branch name.
#
# Every frame has the same elements in the same order: the mark glides between them.
# `zsh startup.zsh --face <p|l> <rest|passed|failed|running|waiting|cancelled|none|armed> [age] [workflow name]` prints
# one frame (rest.svg, rest-landscape.svg, demo.svg and demo-landscape.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP

# MARK: - Face

# ci_frame <layout> <state> [age] [name…]. layout p = 2×1 (400×200), l = the 1×2 turned variant (200×400). rest: a
# dashed ring alone, large (the face before the script runs); passed, failed, cancelled: the run ended (green ✓, red ✗,
# grey ✗); running: queued or going (an orange dashed ring around ●); waiting: someone must approve it (orange ●);
# armed: the long press waits for the second one (orange ↻); none: no run can be shown (a grey "—", large, no words).
# age is "<1m", "5m", "3h", "2d"; the name is the workflow's, fitted to at most two lines.
ci_frame() {
  emulate -L zsh
  export LC_ALL=C
  local layout=${1:-p} state=${2:-rest} age=${3:-}
  (( $# > 3 )) && shift 3 || set --
  local name="$*"
  [[ $layout == (p|l) ]] || layout=p
  [[ $state == (rest|passed|failed|running|waiting|cancelled|none|armed) ]] || state=rest
  [[ $age == (\<1m|<->[mhd]) ]] || age=""
  CI_NAME=$name awk -v ly=$layout -v st=$state -v age="$age" '
    function f(x) { return sprintf("%.2f", x) }
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }

    # --- the name: UTF-8 characters with their widths in ems of the system font (semibold) ---
    function kind(c) { return (c < "\200") ? 1 : (c < "\300") ? 0 : (c < "\340") ? 2 : (c < "\360") ? 3 : 4 }
    function ascii(c,   i) {
      if (!nasc) {
        ASC = " !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
        nasc = split("0.215 0.310 0.454 0.637 0.642 0.881 0.702 0.278 0.373 0.373 0.444 0.642 0.248 0.449 0.248 0.305 " \
          "0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.642 0.248 0.248 0.642 0.642 0.642 0.528 0.895 " \
          "0.683 0.640 0.714 0.705 0.578 0.553 0.731 0.731 0.263 0.547 0.647 0.549 0.862 0.722 0.756 0.616 0.756 " \
          "0.638 0.630 0.607 0.716 0.673 0.962 0.679 0.658 0.638 0.373 0.305 0.373 0.642 0.571 0.508 0.543 0.594 " \
          "0.541 0.594 0.552 0.350 0.590 0.580 0.240 0.240 0.532 0.241 0.856 0.571 0.570 0.591 0.590 0.358 0.510 " \
          "0.349 0.571 0.525 0.776 0.519 0.533 0.506 0.373 0.245 0.373 0.642", AW, " ")
      }
      i = index(ASC, c)
      return i ? AW[i] : 0.64
    }
    # Where a line may end after character j: 2 at a space, after a dot, before "("; 1 (only if the line has no 2) at
    # camelCase, "-", "_", "/"; 0 inside a word.
    function brk(j) {
      if (j >= n) return 2
      if (ch[j] == " " || ch[j] == "." || ch[j + 1] == " " || ch[j + 1] == "(") return 2
      if ((ch[j] ~ /[a-z]/ && ch[j + 1] ~ /[A-Z]/) || index("-_/", ch[j])) return 1
      return 0
    }
    function put(s, e, extra,   j, t) {         # line nl = characters s…e, trailing spaces dropped
      while (e >= s && ch[e] == " ") e--
      t = ""
      for (j = s; j <= e; j++) t = t ch[j]
      L[nl] = t extra
    }
    # Lays the name out in at most maxl lines of b ems, breaking only where brk() allows; 0 when it does not fit. With
    # clip it never fails: the first line it cannot finish is cut to what fits and ends the name with "…".
    function lay(b, maxl, clip,   s, e, x, j, bp) {
      nl = 0; s = 1
      while (s <= n) {
        while (s <= n && ch[s] == " ") s++
        if (s > n) break
        nl++; x = 0; e = s - 1
        while (e < n && x + w[e + 1] <= b) { e++; x += w[e] }
        if (e == n) { put(s, n, ""); return 1 }
        bp = 0
        if (nl < maxl) {
          for (j = e; j >= s && !bp; j--) if (brk(j) == 2) bp = j
          for (j = e; j >= s && !bp; j--) if (brk(j) == 1) bp = j
        }
        if (!bp) {
          if (!clip) return 0
          x = 0; e = s - 1
          while (e < n && x + w[e + 1] <= b - 0.68) { e++; x += w[e] }   # 0.68 em: "…"
          while (e >= s && index(" .-_/(", ch[e])) e--
          put(s, e, "…")
          return 1
        }
        put(s, bp, "")
        s = bp + 1
      }
      return 1
    }

    BEGIN {
      # mark colour; ring dashes (rest, running) or solid; which inner mark shows; bloom opacity; words shown
      grey = "#8E8E93"; c = grey; dash = 0; mk = ""; bA = 0.10; words = 1
      if (st == "rest")      { c = "#FFFFFF"; dash = 1; bA = 0.06; words = 0 }
      if (st == "passed")    { c = "#32D74B"; mk = "check"; bA = 0.22 }
      if (st == "failed")    { c = "#FF453A"; mk = "cross"; bA = 0.34 }
      if (st == "running")   { c = "#FF9F0A"; dash = 1; mk = "dot"; bA = 0.22 }
      if (st == "waiting")   { c = "#FF9F0A"; mk = "dot"; bA = 0.22 }
      if (st == "armed")     { c = "#FF9F0A"; mk = "arrow"; bA = 0.34 }
      if (st == "cancelled") { mk = "cross"; bA = 0.08 }
      if (st == "none")      { mk = "dash"; bA = 0.04; words = 0 }
      if (age == "") words = 0

      # the mark: a ring of radius 50 around the origin, moved and scaled; large and centred when there are no words
      if (ly == "p") { W = 222; tx = 160; if (words) { gx = 84; gy = 100; k = 1 } else { gx = 200; gy = 100; k = 1.3 } }
      else           { W = 184; tx = 100; if (words) { gx = 100; gy = 98; k = 1 } else { gx = 100; gy = 200; k = 1.3 } }
      ringO = (st == "rest") ? 0.55 : (st == "none" || st == "cancelled") ? 0.70 : 1
      da = dash ? "11 8.63" : "314.16 0"         # 16 dashes on the ring (2π·50 = 314.16), or one unbroken stroke

      # --- the words: the name in the biggest size for its line count (one line up to 34, two up to 30, never under
      # 28), cut with "…" when even two lines at 28 cannot hold it; the age under it with a small clock ---
      nm = ENVIRON["CI_NAME"]
      gsub(/[\001-\037\177]/, "", nm)
      n = 0
      for (i = 1; i <= length(nm); i++) {
        ch1 = substr(nm, i, 1); t = kind(ch1)
        if (t == 0) { if (n) ch[n] = ch[n] ch1; continue }
        n++; ch[n] = ch1; w[n] = (t == 1) ? ascii(ch1) : (t == 2) ? 0.58 : (t == 3) ? 1 : 1.15
      }
      if (n == 0) { n = 1; ch[1] = "—"; w[1] = 1 }
      cap[1] = 34; cap[2] = 30; best = -1
      for (m = 1; m <= 2; m++)
        for (sz = cap[m]; sz >= 28; sz -= 2)
          if (lay(W / sz, m, 0)) { if (sz - 3 * (m - 1) > best) { best = sz - 3 * (m - 1); bm = m; bs = sz }; break }
      if (best >= 0) { sz = bs; lay(W / sz, bm, 0) } else { sz = 28; lay(W / sz, 2, 1) }
      if (!words) { sz = 30; nl = 1; L[1] = "—" }
      if (nl < 2) L[2] = "—"                     # never an empty <text>: the structure must not change
      lh = sz * 1.16; as = 28; gap = 10
      total = nl * lh + gap + as
      yc = (ly == "p") ? 100 : 266
      top = yc - total / 2
      y1 = top + lh / 2; y2 = (nl > 1) ? y1 + lh : y1
      ya = top + nl * lh + gap + as / 2
      o1 = words ? 1 : 0; o2 = (words && nl > 1) ? 1 : 0; oa = words ? 0.65 : 0
      if (age == "") age = "—"
      aw = 0
      for (i = 1; i <= length(age); i++) aw += (substr(age, i, 1) == "<") ? 0.642 : ascii(substr(age, i, 1))
      aw *= as
      if (ly == "p") cx = tx + 10; else cx = tx + 10 - (28 + aw) / 2   # the clock and the age, centred when turned
      ax = cx + 18; anchor = "start"

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %s\"><defs>", (ly == "p") ? "400 200" : "200 400"
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", c, f(bA), c, f(bA * 0.35), c
      printf "<circle id=\"bloom\" cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"url(#bloomG)\"/>", f(gx), f(gy), f(92 * k)
      printf "<g id=\"mark\" transform=\"translate(%s %s) scale(%s)\" fill=\"none\" stroke=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-linejoin=\"round\">", f(gx), f(gy), f(k), c
      printf "<circle id=\"ring\" cx=\"0\" cy=\"0\" r=\"50\" stroke-dasharray=\"%s\" opacity=\"%s\"/>", da, f(ringO)
      printf "<path id=\"check\" d=\"M -22 1 L -7 16 L 23 -16\" opacity=\"%d\"/>", (mk == "check")
      printf "<path id=\"cross\" d=\"M -17 -17 L 17 17 M 17 -17 L -17 17\" opacity=\"%d\"/>", (mk == "cross")
      printf "<circle id=\"dot\" cx=\"0\" cy=\"0\" r=\"16\" fill=\"%s\" stroke=\"none\" opacity=\"%d\"/>", c, (mk == "dot")
      printf "<path id=\"dash\" d=\"M -20 0 L 20 0\" opacity=\"%d\"/>", (mk == "dash")
      printf "<path id=\"arrow\" d=\"M 20.78 -12 A 24 24 0 1 1 0 -24 M -8 -32 L 1 -24 L -8 -16\" opacity=\"%d\"/>", (mk == "arrow")
      printf "</g>"
      printf "<text id=\"name1\" x=\"%s\" y=\"%s\" font-size=\"%d\" font-weight=\"600\" text-anchor=\"%s\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" opacity=\"%d\">%s</text>", f(tx), f(y1), sz, (ly == "p") ? "start" : "middle", o1, esc(L[1])
      printf "<text id=\"name2\" x=\"%s\" y=\"%s\" font-size=\"%d\" font-weight=\"600\" text-anchor=\"%s\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" opacity=\"%d\">%s</text>", f(tx), f(y2), sz, (ly == "p") ? "start" : "middle", o2, esc(L[2])
      printf "<g id=\"clock\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"2.5\" stroke-linecap=\"round\" opacity=\"%s\">", f(oa)
      printf "<circle cx=\"%s\" cy=\"%s\" r=\"10\"/>", f(cx), f(ya)
      printf "<path d=\"M %s %s L %s %s L %s %s\"/></g>", f(cx), f(ya - 6), f(cx), f(ya), f(cx + 5), f(ya + 3)
      printf "<text id=\"age\" x=\"%s\" y=\"%s\" font-size=\"%d\" font-weight=\"600\" text-anchor=\"%s\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" opacity=\"%s\">%s</text>", f(ax), f(ya), as, anchor, f(oa), esc(age)
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  ci_frame "$@"
  exit 0
fi

# MARK: - What runs

[[ -n $own ]] || { print -u2 -- "Branch CI: DESMAPTIC_STORAGE is not set"; exit 1 }
zf_mkdir -p "$own" 2>/dev/null

period=60                                       # seconds between looks while the button is on screen
retry=30                                        # … after a passing hitch, or a face the agent did not take
stale=900                                       # seconds after the last answer when a hitch greys the run out

told=""
tell() {   # logs a reason once, not on every look
  [[ $1 == "$told" ]] && return
  told=$1
  print -ru2 -- "Branch CI: $1"
}

# report <kind> <message> | report clear: tells the phone why there is no run to show, on a change; clear once there
# is again. Remembered only when the agent took it (200), so a refused one is posted again at the next look.
said=""
report() {
  local want="" json
  [[ $1 == clear ]] || want="$1 $2"
  [[ $want == "$said" ]] && return 0
  if [[ -z $want ]]; then
    json="{\"cellId\":\"$cell\",\"clear\":true}"
  else
    json=$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')
  fi
  [[ $(call error "$json") == 200 ]] && said=$want
  return 0
}

# What the face shows: the run's state, when it ran (epoch seconds) and its workflow's name.
shows=rest ran=0 workflow="" good=0

# trouble <kind> <message>: nothing to show until the user acts (or a run comes) — the grey "—", the reason to the phone
# and to the presses.
trouble() {
  tell "$2"
  report $1 "$2"
  print -r -- "$1 $2" > "$own/problem" 2>/dev/null
  zf_rm -f "$own/run" 2>/dev/null
  shows=none
}

# hitch <kind> <message>: out of the user's hands for now — the reason to the phone, the last run stays until it is
# $stale seconds old.
hitch() {
  if (( EPOCHSECONDS - good > stale )); then trouble "$@"; return; fi
  tell "$2"
  report $1 "$2"
}

# ci_pick: jq over the push and the pull_request runs (--slurpfile push, pr; the Actions API's answers) → one line: id,
# status, conclusion ("-" while there is none), address, when it ran, then the name (it may hold spaces); "none" when
# there is no run; nothing for an answer it cannot read. The runs kept are the repository's own (not a fork's) of the
# newest commit; of them the worst is shown, and tapped and rerun: failed, then going, then waiting, then cancelled,
# then passed; the newest of equals. When: the end of a finished run, the start of one that is going; never before it
# was made (a queued run has no start yet).
ci_pick='if ($push[0].workflow_runs | type) != "array" or ($pr[0].workflow_runs | type) != "array" then empty
  else [($push[0].workflow_runs + $pr[0].workflow_runs)[]
        | select(type == "object" and .head_repository.full_name? != null
                 and .head_repository.full_name? == .repository.full_name?)]
  | sort_by(.created_at // "") | reverse
  | if length == 0 then "none"
    else .[0].head_sha as $sha
    | [.[] | select(.head_sha == $sha)
        | . + {worst: (if .status != "completed" then 1
                       elif .conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure" then 0
                       elif .conclusion == "action_required" then 2
                       elif .conclusion == "success" or .conclusion == "neutral" or .conclusion == "skipped" then 4
                       else 3 end)}]
    | sort_by(.worst) | .[0]
    | ((.created_at // "") | try fromdateiso8601 catch 0) as $made
    | ((if .status == "completed" then .updated_at else .run_started_at end) // "" | try fromdateiso8601 catch 0) as $when
    | [(.id | tostring), .status, (.conclusion // "" | if . == "" then "-" else . end), .html_url,
       ([$made, $when] | max | floor | tostring), (.name // "" | gsub("[\t\n\r]"; " "))]
    | join("\t")
    end
  end'

default_of="" default_branch=""
# look: asks GitHub for the branch's CI run and sets shows, ran and workflow (or calls trouble or hitch). 0 when it
# got an answer, 1 after a hitch.
look() {
  local br rc row id run_status conclusion url when name
  if find_gh || resolve; then trouble ${REPLY%% *} "${REPLY#* }"; return 0; fi
  br=$branch
  if [[ -z $br && -n $folder ]]; then
    limited 10 $vcs -C "$folder" symbolic-ref -q --short HEAD
    rc=$?                                       # 1: a detached HEAD; anything else: no repository there
    br=""; IFS= read -r br < "$tmp/out"
    if (( rc == 1 )); then
      trouble config "The folder’s repository isn’t on a branch. Check one out, or set the branch in the button’s settings."
      return 0
    elif (( rc != 0 )) || [[ -z $br ]]; then
      trouble config "The folder in the button’s settings isn’t a GitHub repository."
      return 0
    fi
  elif [[ -z $br ]]; then
    if [[ $default_of != "$slug" ]]; then
      # gh repo view takes the repository as its argument, not -R
      local keep=$slug
      slug=""
      run_gh 20 repo view $keep --json defaultBranchRef --jq .defaultBranchRef.name
      rc=$?
      slug=$keep
      default_branch=""; IFS= read -r default_branch < "$tmp/out"
      if (( rc != 0 )) || [[ -z $default_branch ]]; then
        refusal $rc
        [[ $REPLY == (network|timeout|busy)\ * ]] && { hitch ${REPLY%% *} "${REPLY#* }"; return 1 }
        trouble ${REPLY%% *} "${REPLY#* }"
        return 0
      fi
      default_of=$slug
    fi
    br=$default_branch
  fi
  # The branch's CI is the runs of its latest commit for a push or a pull request. GitHub is asked for those two events
  # only: the branch's newest runs are often scheduled jobs, comments or runs started by other runs, and those can fill
  # any number of the newest. The API, not gh run list, as it tells a pull request from a fork whose branch has the same
  # name: such runs are a stranger's commit, and left out. gh fills {owner}/{repo} in for a folder.
  local where=${slug:-"{owner}/{repo}"} keep=$slug event
  where="repos/$where/actions/runs?branch=$(jq -rn --arg b "$br" '$b | @uri')&per_page=30&event="
  slug=""
  for event in push pull_request; do
    run_gh 20 api "$where$event"
    rc=$?
    (( rc == 0 )) || break
    mv -f "$tmp/out" "$tmp/$event"
  done
  slug=$keep
  if (( rc != 0 )); then
    refusal $rc
    [[ $REPLY == (network|timeout|busy|other)\ * ]] && { hitch ${REPLY%% *} "${REPLY#* }"; return 1 }
    trouble ${REPLY%% *} "${REPLY#* }"
    return 0
  fi
  row=$(jq -rn --slurpfile push "$tmp/push" --slurpfile pr "$tmp/pull_request" "$ci_pick" 2>/dev/null)
  if [[ $row == none ]]; then
    trouble notFound "This branch has no GitHub Actions runs for a push or a pull request yet."
    return 0
  fi
  IFS=$'\t' read -r id run_status conclusion url when name <<< "$row"
  if [[ $id != <-> || $url != https://github.com/*/actions/runs/$id ]]; then
    hitch other "GitHub sent a run the button can’t read."
    return 0
  fi
  told=""
  report clear
  good=$EPOCHSECONDS
  zf_rm -f "$own/problem" 2>/dev/null
  print -rl -- "id=$id" "url=$url" "status=$run_status" "conclusion=$conclusion" > "$own/run.new" 2>/dev/null &&
    mv -f "$own/run.new" "$own/run" 2>/dev/null
  [[ $when == <-> ]] && ran=$when || ran=$EPOCHSECONDS
  workflow=$name
  if [[ $run_status != completed ]]; then
    shows=running
  else
    case $conclusion in
      (success|neutral|skipped)            shows=passed ;;
      (failure|timed_out|startup_failure)  shows=failed ;;
      (action_required)                    shows=waiting ;;
      (*)                                  shows=cancelled ;;
    esac
  fi
  return 0
}

# ago <epoch>: REPLY = how long ago, in the face's units.
ago() {
  local s=$(( EPOCHSECONDS - $1 ))
  if (( s < 60 )); then REPLY="<1m"
  elif (( s < 3600 )); then REPLY="$(( s / 60 ))m"
  elif (( s < 172800 )); then REPLY="$(( s / 3600 ))h"
  else REPLY="$(( s / 86400 ))d"
  fi
}

# MARK: - Loop

hidden=0 looked=0
visible() {   # does the phone show the button (or is it too old to say)? Asks at most every 5 s while it does not.
  local out code body
  (( hidden && EPOCHSECONDS - looked < 5 )) && return 1
  looked=$EPOCHSECONDS
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || { hidden=1; return 1 }
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  if [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]; then
    hidden=0
  else
    hidden=1
  fi
  (( ! hidden ))
}

# draw <state>: posts the face of that state with the run's age and name, both layouts → 0 when the agent took it.
draw() {
  local p l out code age=""
  if [[ $1 != (none|rest) ]]; then ago $ran; age=$REPLY; fi
  p=$(ci_frame p $1 "$age" "$workflow") l=$(ci_frame l $1 "$age" "$workflow")
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  l=${l//\\/\\\\}; l=${l//\"/\\\"}; l=${l//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    --data-binary @- <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"landscapeSource\":\"$l\",\"duration\":0.6}}")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Branch CI: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# The face: what the long press holds (armed for 10 s, rerun until GitHub shows the run going or 45 s pass) over the run.
hold_state() {
  local line="" verb at
  [[ -f $own/hold ]] && IFS= read -r line < "$own/hold" 2>/dev/null
  verb=${line%% *} at=${line#* }
  if [[ $verb == armed && $at == <-> ]] && (( EPOCHSECONDS - at <= 10 )) && [[ $shows == failed || $shows == cancelled ]]; then
    REPLY=armed
  elif [[ $verb == rerun && $at == <-> ]] && (( EPOCHSECONDS - at <= 45 )) && [[ $shows != running ]]; then
    REPLY=running
  else
    [[ -n $line ]] && zf_rm -f "$own/hold" 2>/dev/null
    REPLY=$shows
  fi
}

# Every look sends its face, changed or not: the age moves on, and a face reset from outside (the user saving the
# button) comes back within one look. Between looks the face changes only for a press: the presses poke the loop, and
# the hold file is read only then, after a look, or while it holds something that runs out. The loop wakes once a
# second, like the GitHub page's buttons.
shown=rest poked="" due=0 held=1   # the rest face stays until the first look
while true; do
  poke=""
  [[ -f $own/poke ]] && IFS= read -r poke < "$own/poke" 2>/dev/null
  if [[ -n $poke && $poke != "$poked" ]]; then
    poked=$poke shown="" held=1
    # after a rerun: it takes a moment to show as queued
    [[ $poke == *\ look ]] && (( due > EPOCHSECONDS + 3 )) && due=$(( EPOCHSECONDS + 3 ))
  fi
  if (( EPOCHSECONDS >= due )) && visible; then
    look && due=$(( EPOCHSECONDS + period )) || due=$(( EPOCHSECONDS + retry ))
    shown="" held=1
  fi
  if (( held )); then
    hold_state
    face=$REPLY
    [[ $face == "$shows" ]] && held=0          # nothing held: no need to read the file again until a poke
  fi
  if [[ $face != "$shown" ]]; then
    draw $face || due=$(( EPOCHSECONDS + retry ))   # the agent is busy or restarting: again at the next look
    shown=$face
  fi
  zselect -t 100
done
