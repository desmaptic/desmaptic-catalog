# GitHub › New PR: opens GitHub's page for a new pull request from the folder's current branch (`gh pr create
# --web`), where the title and description are written and the pull request is made. After the setting and gh.zsh
# (app.json): "repo=\"\"   # ← …\n@file:gh.zsh\n@file:new-pr.zsh".
#
# Nothing leaves the Mac: the branch must already be on GitHub under its own name with the commit the Mac is on —
# otherwise the button says to push it (gh itself would push, or fork the repository, when it could ask). A branch
# that already has an open pull request opens that one instead.

ready
branch
br=$REPLY
call update-button "{\"cellId\":\"$cell\",\"icon\":\"hourglass\"}" >/dev/null

# The upstream: <remote>/<branch>, the same name as the local branch, and the same commit.
limited 10 $vcs -C "$folder" rev-parse -q --abbrev-ref --symbolic-full-name '@{upstream}'
up=$(first_line $tmp/out)
[[ -n $up ]] || fail config "$br is not on GitHub yet: push it first"
[[ ${up#*/} == "$br" ]] || fail config "$br follows $up, not a branch of its own on GitHub: push it under its own name first"
limited 10 $vcs -C "$folder" rev-parse -q --verify HEAD
head=$(first_line $tmp/out)
limited 10 $vcs -C "$folder" rev-parse -q --verify '@{upstream}'
[[ -n $head && $(first_line $tmp/out) == "$head" ]] || fail config "$br has commits GitHub does not have yet: push them first"

run_gh 20 repo view --json defaultBranchRef --jq .defaultBranchRef.name
rc=$?
if (( rc != 0 )); then
  gh_refusal $rc "gh repo view"
  fail ${REPLY%% *} "${REPLY#* }"
fi
[[ $(first_line $tmp/out) == "$br" ]] && fail config "$br is the repository’s default branch: switch to the branch of your change"

run_gh 20 pr view --json url,state
rc=$?
if (( rc == 0 )); then
  url=$(jq -r 'if .state == "OPEN" then .url else empty end' "$tmp/out" 2>/dev/null)
  if [[ -n $url ]]; then
    open_url "$url"
    flash arrow.up.forward.app
    exit 0
  fi
elif [[ $(first_line $tmp/err) != *no\ pull\ requests\ found* ]]; then
  gh_refusal $rc "gh pr view"
  fail ${REPLY%% *} "${REPLY#* }"
fi

# --web: gh prints the address and opens it with `open`, which here gets gh's clean environment, not the agent's.
run_gh 30 pr create --web
rc=$?
if (( rc != 0 )); then
  err=$(first_line $tmp/err)
  [[ $err == *(must\ first\ push|--head\ flag)* ]] && fail config "$br is not on GitHub yet: push it first"
  [[ $err == *(No\ commits\ between|same\ as\ base)* ]] && fail config "$br has no commits that its base branch lacks"
  gh_refusal $rc "gh pr create"
  fail ${REPLY%% *} "${REPLY#* }"
fi
flash checkmark
exit 0
