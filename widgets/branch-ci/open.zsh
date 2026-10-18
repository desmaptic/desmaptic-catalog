# Branch CI › tap: opens the last run the loop saw (gallery/{{CELL_ID}}/run) on GitHub in the browser. After common.zsh
# (item.json): "@file:common.zsh\n@file:open.zsh". A grey face's tap says what it means instead.

loop_said
read_run
[[ ${run[id]} == <-> ]] || fail notFound "The button hasn’t seen a GitHub Actions run of this branch yet. It checks while it’s on screen."
[[ ${run[url]} == https://github.com/[A-Za-z0-9-]##/[A-Za-z0-9._-]##/actions/runs/${run[id]} ]] ||
  fail other "GitHub didn’t give the run’s address."
# env -i: the browser gets the account's own environment, as from the Dock, not the agent's token. Its complaints go
# nowhere: they would name the run's address, and so its repository, in the log.
env -i /usr/bin/open -- "${run[url]}" 2>/dev/null || fail other "The browser didn’t open the run."
exit 0
