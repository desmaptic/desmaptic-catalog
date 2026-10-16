# GitHub › CI › long press: reruns the failed jobs of the last run its loop saw (`gh run rerun <id> --failed`),
# confirmed by a second long press within 10 seconds. After gh.zsh (app.json): "@file:gh.zsh\n@file:ci/rerun.zsh".
#
# The first long press only arms it: the button turns orange with a circling arrow and gallery/{{CELL_ID}}/armed
# holds the time, which the loop leaves alone for 10 s. A second one in that time reruns; later, it arms again. A grey
# triangle's long press says what it means instead.

loop_said
typeset -A run
if [[ -n $own && -f $own/run ]]; then
  for line in ${(f)"$(<$own/run)"}; do run[${line%%=*}]=${line#*=}; done
fi
[[ ${run[id]} == <-> ]] || fail notFound "No GitHub Actions run of this branch yet (or the button has not looked: it looks while it is on screen)"
[[ ${run[status]} == completed ]] || fail busy "The last run is still going: nothing to rerun yet"
[[ ${run[conclusion]} == (failure|timed_out|cancelled) ]] || fail other "The last run did not fail: nothing to rerun"

armed=""
[[ -f $own/armed ]] && IFS= read -r armed < "$own/armed" 2>/dev/null
if ! [[ $armed == <-> ]] || (( EPOCHSECONDS - armed > 10 )); then
  zf_mkdir -p "$own" 2>/dev/null
  print -r -- $EPOCHSECONDS > "$own/armed" 2>/dev/null || fail permission "The button cannot keep its state in the agent’s folder"
  call update-button "{\"cellId\":\"$cell\",\"color\":\"#FF9F0A\",\"icon\":\"arrow.clockwise.circle\"}" >/dev/null
  exit 0
fi
zf_rm -f "$own/armed" 2>/dev/null

folder=${run[folder]} slug=${run[slug]}
[[ -n $folder || -n $slug ]] || fail config "The button does not know the repository yet: wait for its next look"
call update-button "{\"cellId\":\"$cell\",\"icon\":\"hourglass\"}" >/dev/null
run_gh 30 run rerun ${run[id]} --failed
rc=$?
if (( rc != 0 )); then
  gh_refusal $rc "gh run rerun"
  fail ${REPLY%% *} "${REPLY#* }"
fi
flash checkmark
exit 0
