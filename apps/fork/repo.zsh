# Fork › Open Repo: Fork's own command-line helper, the one inside the app (not the `fork` link its installer may
# make). Launch Services finds the app by its bundle id, wherever it is installed. The helper hands the repository to
# the running Fork, or starts Fork; Fork opens it in a tab, or brings its tab forward, and comes to the front. It
# works with Fork in the background or closed, and no permission is needed.
# Checked in Fork 2.70.1: `fork [<options>] <command>`, `-C /path/to/repository`, `log` — the revision list,
# `status` — the Commit view. The helper reaches Fork through NSDistributedNotificationCenter's
# postNotificationName:object:userInfo:deliverImmediately: only — no all-sessions option, so only this login
# session's Fork hears it (not Darwin notifications, which reach every account: apps/proxyman/action.zsh).
# The tap's command starts with the repository, which the user sets, then its action and this file (app.json); the
# long press has no setting of its own: it opens the repository the tap opened last, which the tap keeps under
# gallery/<cell>/ (the tap and the long press share the cell).
#   "repo=\"\"   # ← …\naction=log\n@file:repo.zsh"
#   "action=status\n@file:repo.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/zselect zsh/datetime || { print -u2 -- "Open Repo: zsh modules zselect and datetime are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir || { print -u2 -- "Open Repo: zsh module files is missing"; exit 1 }

[[ -n $DESMAPTIC_STORAGE ]] && saved="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}/repo" || saved=""
case $action in
  log)
    [[ -n $repo ]] || { print -u2 -- "Open Repo: set your repository’s folder in this button’s settings, such as repo=\"~/Projects/app\""; exit 1 }
    [[ $repo == '~/'* ]] && repo=$HOME/${repo#\~/}              # "~/…" in quotes is not expanded by zsh
    [[ $repo == /* ]] || { print -u2 -- "Open Repo: the folder must start with / or ~/"; exit 1 } ;;
  status)
    [[ -n $saved && -f $saved ]] && repo=$(<$saved)
    [[ -n $repo ]] || { print -u2 -- "Open Repo: tap the button once first — the long press opens the repository the tap opened"; exit 1 } ;;
  *) print -u2 -- "Fork: unknown action \"$action\""; exit 1 ;;
esac
[[ -d $repo ]] || { print -ru2 -- "Open Repo: no folder at $repo"; exit 1 }
# A repository's top folder holds its .git folder, or a .git file in a linked worktree.
marker=($repo/.git(N))  # not a call: the repository's own folder
(( $#marker )) || { print -ru2 -- "Open Repo: $repo is not the top folder of a Git repository"; exit 1 }

app=$(osascript -l JavaScript -e 'function run(argv) {
  ObjC.import("AppKit");
  const url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(argv[0]);
  return url.isNil() ? "" : url.path.js;
}' com.DanPristupov.Fork 2>/dev/null)
[[ $app == /* ]] || { print -u2 -- "Fork is not installed"; exit 1 }
cli="$app/Contents/Resources/fork_cli"
[[ -f $cli && -x $cli ]] || { print -u2 -- "Fork's command-line helper is missing from the app"; exit 1 }

# The helper waits for the running Fork to answer before it starts one; a Fork that never answers must not hold the
# button, so it runs in the background as the command itself, where $! can be stopped after 20 s. It starts a closed
# Fork through NSWorkspace, which passes the helper's environment on to Fork — and from there to its terminal and
# custom commands: the agent's token and this script's PATH and LC_ALL. So it runs with none, and Fork gets the
# account's ordinary one, as from the Dock.
env -i "$cli" -C "$repo" $action >/dev/null 2>&1 </dev/null &
pid=$!
(( deadline = EPOCHREALTIME + 20 ))
while kill -0 $pid 2>/dev/null && (( EPOCHREALTIME < deadline )); do
  zselect -t 10
done
if kill -0 $pid 2>/dev/null; then
  kill $pid 2>/dev/null
  print -u2 -- "Fork did not answer"
  exit 1
fi
wait $pid || { print -u2 -- "Fork did not open the repository"; exit 1 }

if [[ $action == log && -n $saved ]]; then
  zf_mkdir -p "${saved:h}" 2>/dev/null && print -r -- "$repo" > "$saved" 2>/dev/null
fi
exit 0
