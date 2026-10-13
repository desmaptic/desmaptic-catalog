# Docker Desktop › Containers, the long press: stops every running container of Docker Desktop's engine, as
# `docker stop $(docker ps -q)` does — each container gets its own stop signal and grace period (10 s unless it set
# another), all at once. Stopped, not removed — except a container started with `--rm`, which Docker itself removes
# once it stops (hence the ⚠️ on the long press); Start in the Dashboard brings the others back. The command is
# cli.zsh and then this file (app.json).
#
# Without Docker Desktop, or with its VM stopped (Resource Saver), no container runs and nothing is asked.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

desktop_running || exit 0
engine_running || exit 0
docker_cli || { print -ru2 -- "$REPLY"; exit 1 }
cli=$REPLY

if ! out=$(docker_engine "$cli" ps -q 2>&1 </dev/null); then
  out=${out%%$'\n'*}                         # its first line
  print -ru2 -- "Docker did not list the containers: ${out[1,200]:-no answer}"
  exit 1
fi
ids=()
for id in ${(f)out}; do
  [[ $id =~ '^[0-9a-f]{12,64}$' ]] && ids+=( $id )
done
(( $#ids )) || exit 0                           # none running

poke_widgets
if ! out=$(docker_engine "$cli" stop -- "${ids[@]}" 2>&1 >/dev/null </dev/null); then
  out=${out%%$'\n'*}                         # its first line
  print -ru2 -- "Not every container stopped: ${out[1,200]:-no answer}"
  poke_widgets
  exit 1
fi
poke_widgets
exit 0
