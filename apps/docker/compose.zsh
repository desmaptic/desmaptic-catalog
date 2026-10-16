# Docker Desktop › Compose Up: the tap starts a whole compose project in the background (`docker compose up -d`: the
# database, the cache, the API — whatever its compose.yaml lists), the long press takes it down (`docker compose down`:
# its containers and networks are stopped and removed, its volumes and images stay). Each command is the project's
# folder, a line that names its action, then cli.zsh and this file (app.json):
#   "dir=\"\"   # ← …\naction=up\n@file:cli.zsh\n@file:compose.zsh"   — up or down.
# The folder is the user's to set in the first line of each command; until it is, the button says so.
#
# Both ask Docker Desktop's own engine and need Docker Desktop running (Start on this page). Compose stays within the
# press, which may run 60 s: past 50 s — a first `up` pulling or building images — it is stopped and the button says
# to press again; the layers already pulled stay, so the next `up` goes on from there.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (up|down) ]] || { print -u2 -- "Docker: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Docker: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_rm

# MARK: - The project's folder

if [[ -z $dir ]]; then
  [[ $action == up ]] && script=tap || script="long press"
  print -ru2 -- "Set the folder with your compose.yaml in this button’s settings, for the $script"
  exit 1
fi
[[ $HOME == /?* ]] || { print -u2 -- "Docker: HOME is not set"; exit 1 }
[[ $dir == '~' || $dir == '~/'* ]] && dir=$HOME${dir#'~'}   # "~/…" in quotes is not expanded by the shell
[[ $dir == /* ]] || { print -ru2 -- "The folder must be a full path or start with ~/: $dir"; exit 1 }
[[ -d $dir ]] || { print -ru2 -- "No such folder: $dir"; exit 1 }
# The file names Compose looks for. Checked here: without one in the folder, Compose would look in the folders above.
found=0
for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
  [[ -f $dir/$f ]] && { found=1; break }
done
(( found )) || { print -ru2 -- "No compose.yaml in $dir"; exit 1 }

# MARK: - Docker Desktop

desktop_running || { print -u2 -- "Docker Desktop is not running: start it first"; exit 1 }
docker_cli || { print -ru2 -- "$REPLY"; exit 1 }
cli=$REPLY
# The CLI's own folder first: it holds docker-credential-desktop, which pulls and builds run for "credsStore": "desktop"
# (~/.docker/config.json) — a helper missing from PATH is an error, not "no credentials".
PATH="${cli:h}:$PATH"
[[ -n $DESMAPTIC_STORAGE ]] || { print -u2 -- "Docker: DESMAPTIC_STORAGE is not set"; exit 1 }
state="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"  # compose's output, one file per action
zf_mkdir -p "$state" 2>/dev/null
out="$state/$action"

# MARK: - Compose

[[ $action == up ]] && args=(up -d) || args=(down)
poke_widgets
# The CLI itself in the background (not docker_engine, a function: $! would be a subshell, and a stuck CLI would
# outlive its kill). Its settings as docker_engine's.
DOCKER_CLI_HINTS=false DOCKER_CLI_HOOKS=false "$cli" --host "unix://$HOME/.docker/run/docker.sock" \
  compose --ansi never --project-directory "$dir" "${args[@]}" > "$out" 2>&1 < /dev/null &
asker=$!
trap 'pkill -P $asker 2>/dev/null; kill $asker 2>/dev/null; exit 1' TERM INT HUP

deadline=$(( EPOCHSECONDS + 50 ))               # by the clock: a 0.1 s wait may take longer
while kill -0 $asker 2>/dev/null && (( EPOCHSECONDS < deadline )); do
  zselect -t 10
done
if kill -0 $asker 2>/dev/null; then
  # Still pulling or building: the compose plugin (the CLI's child, its pid taken first: once the CLI is gone, it is
  # no one's child) and the CLI are stopped, then killed if need be.
  procs=( ${(f)"$(pgrep -P $asker 2>/dev/null)"} $asker ) live=( $asker )
  kill ${procs[@]} 2>/dev/null
  deadline=$(( EPOCHSECONDS + 5 ))
  while (( EPOCHSECONDS < deadline )); do
    live=()
    for p in $procs; do kill -0 $p 2>/dev/null && live+=( $p ); done
    (( $#live )) || break
    zselect -t 10
  done
  (( $#live )) && kill -KILL $live 2>/dev/null
  wait $asker 2>/dev/null
  poke_widgets
  [[ $action == up ]] && print -u2 -- "Still pulling or building: tap again to go on" \
                      || print -u2 -- "Still taking the project down: hold again to go on"
  exit 1
fi
wait $asker
rc=$?
poke_widgets
(( rc == 0 )) && exit 0
last=""
for line in ${(f)"$(<$out)"}; do
  [[ $line == *[^[:space:]]* ]] && last=$line   # Compose's last words are its error
done
print -ru2 -- "Compose did not finish: ${last[1,200]:-no answer}"
exit 1
