# Docker Desktop: is it running, is its Linux VM running, where is the docker CLI. Functions only — the scripts of
# the page start with this file (app.json): the Containers widget's loop and its long press, and Start's tap and
# long press. Each function runs with zsh's own options (emulate -L): `zsh -c` reads ~/.zshenv, and an option set
# there must not change what a check means.
#
# Nothing here launches Docker Desktop or wakes its VM: the checks are pgrep and file tests.

# 0 when Docker Desktop runs in this account. Its process is the backend: the app itself has no window (the
# Dashboard is a separate app inside it, and closing that window leaves Docker Desktop running).
desktop_running() {
  emulate -L zsh
  pgrep -xqU $UID com.docker.backend
}

# 0 when Docker Desktop's Linux VM runs: com.docker.virtualization (Apple's Virtualization framework, the default),
# com.docker.krun (Docker VMM) or com.docker.hyperkit (old Intel versions) — Docker's own names, so a VM of another
# tool (Colima, UTM) does not count. Without it no container runs — Resource Saver has stopped it, the engine is
# stopped, or still starting — and asking the engine then could wake a VM Resource Saver put to sleep.
engine_running() {
  emulate -L zsh
  pgrep -xqU $UID 'com\.docker\.(virtualization|krun|hyperkit)'
}

# REPLY = the docker CLI: Docker Desktop's own first (it matches the running app), then the links its installer
# makes (/usr/local/bin, or ~/.docker/bin with "user" CLI tools). A fixed list, never a PATH lookup. 1 with the
# reason in REPLY when there is none.
docker_cli() {
  emulate -L zsh
  local c
  [[ $HOME == /?* ]] || { REPLY="Docker: HOME is not set"; return 1 }
  for c in /Applications/Docker.app/Contents/Resources/bin/docker \
           $HOME/Applications/Docker.app/Contents/Resources/bin/docker \
           /usr/local/bin/docker \
           $HOME/.docker/bin/docker; do
    [[ -f $c && -x $c ]] && { REPLY=$c; return 0 }
  done
  REPLY="Docker's command-line tool was not found: is Docker Desktop in Applications?"
  return 1
}

# docker_engine <cli> <arguments…>: the docker CLI asking Docker Desktop's own engine — its socket, whatever context
# the user switched the CLI to (Colima, a remote host) — with the CLI's hints and plugin hooks off.
docker_engine() {
  emulate -L zsh
  local cli=$1
  shift
  DOCKER_CLI_HINTS=false DOCKER_CLI_HOOKS=false "$cli" --host "unix://$HOME/.docker/run/docker.sock" "$@"
}

# Tells the Containers widget that a button of the page just started or stopped something: its loop looks every
# second for a while (the time in gallery/docker/poke, shared by the app's buttons).
poke_widgets() {
  emulate -L zsh
  zmodload zsh/datetime
  zmodload -F zsh/files b:zf_mkdir
  [[ -n $DESMAPTIC_STORAGE ]] || return 0
  zf_mkdir -p "$DESMAPTIC_STORAGE/gallery/docker" 2>/dev/null
  print -r -- $EPOCHSECONDS > "$DESMAPTIC_STORAGE/gallery/docker/poke" 2>/dev/null
  return 0
}
