# Docker Desktop › Start: the tap starts Docker Desktop, the long press quits it. Each command is one line that names
# its action, then cli.zsh and this file (app.json):
#   "action=start\n@file:cli.zsh\n@file:power.zsh" — starts Docker Desktop through Launch Services, as a double click
#       on Docker in Applications does, but in the background (open -g); nothing while it runs already;
#   "action=quit\n…" — quits it with Docker's own command, `docker desktop stop` (Docker Desktop 4.37 and later), as
#       Quit Docker Desktop in its menu does: every container stops with it.
# Neither needs a permission. Both then tell the Containers widget to look every second for a while.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (start|quit) ]] || { print -u2 -- "Docker: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [[ $action == start ]]; then
  if ! desktop_running; then
    # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
    env -i /usr/bin/open -g -b com.docker.docker || { print -u2 -- "Docker Desktop did not start"; exit 1 }
  fi
  poke_widgets
  exit 0
fi

desktop_running || exit 0                       # nothing to quit
docker_cli || { print -ru2 -- "$REPLY"; exit 1 }
cli=$REPLY
poke_widgets
# Waits until Docker Desktop has quit, 45 s at most: a long press may take 60.
if ! out=$(DOCKER_CLI_HINTS=false DOCKER_CLI_HOOKS=false "$cli" desktop stop --timeout 45 2>&1 </dev/null); then
  out=${out%%$'\n'*}                         # its first line
  print -ru2 -- "Docker Desktop did not quit: ${out[1,200]:-no answer}"
  exit 1
fi
poke_widgets
exit 0
