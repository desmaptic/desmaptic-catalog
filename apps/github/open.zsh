# GitHub › Open: the tap opens the repository on GitHub, the long press the pull request of the folder's current
# branch. Each command is the setting, a line that names its action, gh.zsh and this file (app.json):
#   "repo=\"\"   # ← …\naction=repo\n@file:gh.zsh\n@file:open.zsh"   — repo or pr.
# The address comes from gh (`gh browse -n`, `gh pr view`); the browser opens it with the account's own environment.

[[ $action == (repo|pr) ]] || { print -u2 -- "GitHub: unknown action \"$action\""; exit 1 }
ready
if [[ $action == repo ]]; then
  what="gh browse"
  run_gh 20 browse -n
  rc=$?
  url=""
  while IFS= read -r line; do [[ $line == https://* ]] && { url=$line; break }; done < $tmp/out
else
  branch
  br=$REPLY
  what="gh pr view"
  run_gh 20 pr view --json url --jq .url
  rc=$?
  if (( rc != 0 )) && [[ $(first_line $tmp/err) == *no\ pull\ requests\ found* ]]; then
    fail notFound "$br has no pull request yet. Make one with New PR."
  fi
  url=$(first_line $tmp/out)
fi
if (( rc != 0 )); then
  gh_refusal $rc "$what"
  fail ${REPLY%% *} "${REPLY#* }"
fi
open_url "$url"
exit 0
