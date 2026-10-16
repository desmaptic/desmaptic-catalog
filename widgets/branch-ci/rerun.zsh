# Branch CI › long press: reruns the failed jobs of the last run the loop saw (`gh run rerun <id> --failed`), confirmed
# by a second long press within 10 seconds. After common.zsh (item.json): "@file:common.zsh\n@file:rerun.zsh".
#
# The first long press only arms it: gallery/{{CELL_ID}}/hold reads "armed <time>" and the loop shows an orange ↻ for
# 10 s. A second one in that time asks GitHub, and the face shows the run going; later, it arms again. The repository is
# the one in the run's address, so no folder and no Command Line Tools are needed here. A run that did not fail, or a
# grey face, says why instead. Each change of the hold file pokes the loop (gallery/{{CELL_ID}}/poke), which reads the
# hold file only then.

loop_said
read_run
[[ ${run[id]} == <-> ]] || fail notFound "No GitHub Actions run of this branch yet: the button looks while it is on screen"
[[ ${run[status]} == completed ]] || fail busy "The last run is still going: nothing to rerun yet"
[[ ${run[conclusion]} == startup_failure ]] && fail other "The workflow could not start: its file needs a fix, not a rerun"
[[ ${run[conclusion]} == (failure|timed_out|cancelled) ]] || fail other "The last run did not fail: nothing to rerun"
[[ ${run[url]} == https://github.com/(#b)([A-Za-z0-9-]##/[A-Za-z0-9._-]##)/actions/runs/${run[id]} ]] ||
  fail other "GitHub gave no address of the run to rerun"
folder="" slug=$match[1]

hold=""
[[ -f $own/hold ]] && IFS= read -r hold < "$own/hold" 2>/dev/null
at=${hold#armed }
if [[ $hold != armed\ * || $at != <-> ]] || (( EPOCHSECONDS - at > 10 )); then
  print -r -- "armed $EPOCHSECONDS" > "$own/hold" 2>/dev/null || fail permission "The button cannot keep its state in the agent’s folder"
  poke                                          # the loop shows the ↻ now
  exit 0
fi
print -r -- "rerun $EPOCHSECONDS" > "$own/hold" 2>/dev/null
poke                                            # … and the run going while GitHub is asked
run_gh 30 run rerun ${run[id]} --failed
rc=$?
if (( rc != 0 )); then
  zf_rm -f "$own/hold" 2>/dev/null
  refusal $rc
  fail ${REPLY%% *} "${REPLY#* }"
fi
poke look                                       # the loop looks again in a moment: the run shows as queued
exit 0
