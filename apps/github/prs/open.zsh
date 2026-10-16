# GitHub › My PRs › tap: opens the repository's pull requests on GitHub — the repository its loop last asked about
# (gallery/{{CELL_ID}}/where). After gh.zsh (app.json): "@file:gh.zsh\n@file:prs/open.zsh". A grey triangle's tap
# says what it means instead.

loop_said
typeset -A where
if [[ -n $own && -f $own/where ]]; then
  for line in ${(f)"$(<$own/where)"}; do where[${line%%=*}]=${line#*=}; done
fi
folder=${where[folder]} slug=${where[slug]}
[[ -n $folder || -n $slug ]] || fail config "The button does not know the repository yet: set it in this button’s settings, under Advanced"
run_gh 20 browse -n
rc=$?
if (( rc != 0 )); then
  gh_refusal $rc "gh browse"
  fail ${REPLY%% *} "${REPLY#* }"
fi
url=""
while IFS= read -r line; do [[ $line == https://* ]] && { url=$line; break }; done < $tmp/out
open_url "${url%/}/pulls"
exit 0
