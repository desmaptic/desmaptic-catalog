# GitHub › Merge When Green: the tap turns on auto-merge for the pull request of the folder's current branch
# (`gh pr merge --auto`), the long press turns it off (`gh pr merge --disable-auto`). Each command is the settings, a
# line that names its action, gh.zsh and this file (app.json):
#   "repo=\"\"   # ← …\nmethod=\"\"   # ← …\naction=auto\n@file:gh.zsh\n@file:merge.zsh"   — auto or off.
#
# GitHub merges the pull request once its required checks and reviews pass. gh merges at once, without auto-merge,
# whatever GitHub calls mergeable now — CLEAN, HAS_HOOKS, and UNSTABLE: checks that are failing or still running but
# not required, as in every repository without branch protection. So the tap hands the pull request to gh only when
# that cannot merge it past a check that is not green: UNSTABLE, UNKNOWN (not worked out yet) and a CLEAN one with such
# a check are refused; BLOCKED and BEHIND wait on GitHub for what it requires. Only the commit the Mac is on is merged
# (--match-head-commit): with newer commits on GitHub, or ones not pushed yet, GitHub refuses and the button says so.
# The method is the setting (squash, merge or rebase); empty, the one GitHub's page offers you first in that repository
# (your last one there) — gh cannot ask when nothing can answer. Auto-merge must be allowed in the repository's
# settings, or GitHub refuses that too. The branch is never deleted, here or on GitHub.
#
# The repository is never the one last set on another GitHub button (gh.zsh): the tap needs its own setting, and the
# long press takes the tap's (gallery/{{CELL_ID}}/repo) when its own is empty.

[[ $action == (auto|off) ]] || { print -u2 -- "GitHub: unknown action \"$action\""; exit 1 }
if [[ -z $repo && $action == off && -n $own && -f $own/repo ]]; then
  IFS= read -r repo < "$own/repo"
fi
[[ -n $repo ]] ||
  fail config "Merge When Green doesn’t use the repository set on other buttons. Set its folder in this button’s settings, like repo=\"~/Developer/my-app\"."
ready
branch
br=$REPLY
call update-button "{\"cellId\":\"$cell\",\"icon\":\"hourglass\"}" >/dev/null

run_gh 20 pr view --json number,state,isDraft,headRefOid,autoMergeRequest,mergeStateStatus,statusCheckRollup
rc=$?
if (( rc != 0 )); then
  [[ $(first_line $tmp/err) == *no\ pull\ requests\ found* ]] && fail notFound "$br has no pull request yet. Make one with New PR."
  gh_refusal $rc "gh pr view"
  fail ${REPLY%% *} "${REPLY#* }"
fi
typeset -A pr
pr=( ${(f)"$(jq -r '"number", (.number|tostring), "state", .state, "draft", (.isDraft|tostring),
  "head", .headRefOid, "auto", (if .autoMergeRequest then "on" else "off" end), "merge", (.mergeStateStatus // ""),
  "red", ([.statusCheckRollup[]? | .conclusion // .state // "" | select(IN("SUCCESS", "NEUTRAL", "SKIPPED") | not)]
    | length | tostring)' "$tmp/out" 2>/dev/null)"} )
[[ ${pr[number]} == <-> ]] || fail other "GitHub didn’t say which pull request $br has. Try again in a moment."
[[ ${pr[state]} == OPEN ]] || fail other "Pull request #${pr[number]} is already ${(L)pr[state]}."

if [[ $action == off ]]; then
  [[ ${pr[auto]} == on ]] || fail other "Auto-merge isn’t on for #${pr[number]}."
  run_gh 20 pr merge ${pr[number]} --disable-auto
  rc=$?
  if (( rc != 0 )); then
    gh_refusal $rc "gh pr merge --disable-auto"
    fail ${REPLY%% *} "${REPLY#* }"
  fi
  flash xmark.circle "#${pr[number]}"
  exit 0
fi

[[ ${pr[draft]} == false ]] || fail other "Pull request #${pr[number]} is still a draft. Mark it ready for review first."
limited 10 $vcs -C "$folder" rev-parse -q --verify HEAD
head=$(first_line $tmp/out)
[[ $head == ${pr[head]} ]] ||
  fail config "#${pr[number]} on GitHub isn’t at the commit your Mac is on. Push or pull first."
case ${pr[merge]} in
  (UNSTABLE)
    fail config "The checks on #${pr[number]} aren’t green yet, and this repository doesn’t require them. GitHub would merge it right away, so tap once they pass, or make them required." ;;
  (CLEAN|HAS_HOOKS)
    [[ ${pr[red]} == 0 ]] ||
      fail config "The checks on #${pr[number]} aren’t green yet, and this repository doesn’t require them. GitHub would merge it right away, so tap once they pass, or make them required." ;;
  (DIRTY) fail config "#${pr[number]} has conflicts with its base branch. Resolve them first." ;;
  (BLOCKED|BEHIND) ;;
  (*) fail busy "GitHub is still checking whether #${pr[number]} can be merged. Tap again in a moment." ;;
esac

case $method in
  (squash|merge|rebase) ;;
  ('')
    run_gh 20 repo view --json viewerDefaultMergeMethod,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
    rc=$?
    if (( rc != 0 )); then
      gh_refusal $rc "gh repo view"
      fail ${REPLY%% *} "${REPLY#* }"
    fi
    method=$(jq -r '({MERGE: "merge", SQUASH: "squash", REBASE: "rebase"}[.viewerDefaultMergeMethod // ""]
      // (if .squashMergeAllowed then "squash" elif .mergeCommitAllowed then "merge"
          elif .rebaseMergeAllowed then "rebase" else "" end))' "$tmp/out" 2>/dev/null)
    [[ -n $method ]] || fail other "GitHub didn’t say how this repository merges. Set method=\"squash\", \"merge\" or \"rebase\" in the button’s settings." ;;
  (*) fail config "“$method” isn’t a merge method. Use squash, merge or rebase, or leave it empty." ;;
esac

run_gh 40 pr merge ${pr[number]} --auto --$method --match-head-commit $head
rc=$?
if (( rc != 0 )); then
  err=$(first_line $tmp/err)
  [[ $err == *[Aa]uto\ merge\ is\ not\ allowed* ]] &&
    fail config "This repository doesn’t allow auto-merge. Turn on Allow auto-merge in its settings, under General › Pull Requests."
  [[ $err == *([Hh]ead\ branch\ was\ modified|expected\ head)* ]] &&
    fail config "#${pr[number]} changed on GitHub. Pull, then tap again."
  [[ $err == *[Mm]erge\ method*not\ allowed* ]] &&
    fail config "This repository doesn’t allow $method merges. Set another method in the button’s settings."
  gh_refusal $rc "gh pr merge"
  fail ${REPLY%% *} "${REPLY#* }"
fi
# gh says what it did only to a terminal: GitHub says it instead — merged now, or auto-merge on and waiting.
run_gh 20 pr view ${pr[number]} --json state,autoMergeRequest --jq '.state + " " + (if .autoMergeRequest then "auto" else "" end)'
case $(first_line $tmp/out) in
  (MERGED*)    flash checkmark.circle.fill "#${pr[number]}" ;;
  (OPEN\ auto) flash clock.badge.checkmark "#${pr[number]}" ;;
  (*)          flash checkmark "#${pr[number]}" ;;  # queued, or GitHub did not answer: gh said yes
esac
exit 0
