# GitHub › CI › tap: opens the last run its loop saw (gallery/{{CELL_ID}}/run) in the browser. After gh.zsh
# (app.json): "@file:gh.zsh\n@file:ci/open.zsh". A grey triangle's tap says what it means instead.

loop_said
url=""
[[ -n $own && -f $own/run ]] && url=${${(M)${(f)"$(<$own/run)"}:#url=*}#url=}
[[ -n $url ]] || fail notFound "The button hasn’t seen a GitHub Actions run of this branch yet. It checks while it’s on screen."
open_url "$url"
exit 0
