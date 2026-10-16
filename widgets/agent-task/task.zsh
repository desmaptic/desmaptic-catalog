#!/bin/zsh
# Task for an Agent tap: starts Claude Code or Codex in a project folder with the task typed on the phone
# ($DESMAPTIC_INPUT) as its first message — an ordinary interactive session in a new Terminal, iTerm2 or Ghostty window
# or tab, or a new tmux window, so the Mac's terminal owns it and the tap ends within seconds. Cautious by default: the
# session runs in a worktree of its own, on its own branch (the tool's own --worktree), and may not push — Claude Code's
# Bash tool is denied the push command, and for both tools git's configuration in the session's environment sends
# every push to a remote that does not exist. The three settings are the button's first lines: folder, tool,
# terminal; each works when empty. No folder — the one project.zsh (before this file) finds: the last
# Claude Code or Codex session's of the Desmaptic plugin, else the front Terminal, iTerm2, Ghostty or Finder window's
# (a linked worktree found so is taken as its main checkout: the session makes a worktree of its own); with neither,
# the button says where to set it. No tool — Claude Code when it is installed, else Codex. No terminal — the one the
# session the folder came from ran in (else the last plugin session): tmux while the server it ran on still runs,
# else the app, else Terminal. The task goes to the session through a file, not the environment: a new
# tmux window gets the tmux server's environment, not the tap's. The button's command (item.json):
#   "folder=\"\"   # ← …\ntool=\"\"   # ← …\nterminal=\"\"   # ← …\n@file:project.zsh\n@file:task.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Task for an Agent: zsh modules datetime and zselect are missing"; exit 1 }

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
tmp="" run=""
trap '[[ -n $tmp ]] && rm -rf -- "$tmp"' EXIT
trap 'exit 0' TERM INT

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# fail <kind> <message>: the toast after the tap says why (/api/error), then the tap ends — and the session's
# folder, when it was already made, goes with it.
fail() {
  [[ -n $run ]] && rm -rf -- "$run"
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Task for an Agent: $2"
  exit 1
}

# limited <seconds> <program> <arg>…: runs the program with stdin from /dev/null, stdout in $tmp/out and stderr in
# $tmp/err; returns its status, 124 when it ran longer.
limited() {
  local seconds=$1; shift
  "$@" < /dev/null > "$tmp/out" 2> "$tmp/err" &
  local pid=$! deadline=$(( EPOCHREALTIME + seconds ))
  while kill -0 $pid 2>/dev/null; do
    if (( EPOCHREALTIME >= deadline )); then
      kill $pid 2>/dev/null
      return 124
    fi
    zselect -t 20
  done
  wait $pid
}

# started: a moment of ✓ on the button, then its own face again, and the tap ends.
started() {
  call update-button "{\"cellId\":\"$cell\",\"icon\":\"checkmark\"}" >/dev/null
  sleep 1.5
  call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
  exit 0
}

# first_line <file>: the first non-empty line of a file.
first_line() {
  local line
  for line in "${(@f)$(<$1)}"; do
    [[ -n ${line//[[:space:]]/} ]] && { print -r -- "${line[1,200]}"; return }
  done
}

# ---- the settings: each one set, or found ----
found_in=""
if [[ -z $folder ]]; then
  project_folder
  case $? in
    (0) ;;
    (2) fail $project_kind "$project_why, or set the project folder in this button’s settings" ;;
    (*) fail config "No project folder found: no Claude Code or Codex session is running, and no Terminal or Finder window shows a folder. Set one in this button’s settings, e.g. folder=\"~/Developer/my-app\"" ;;
  esac
fi
case $folder in
  '~')   folder=$HOME ;;
  '~/'*) folder=$HOME/${folder#'~/'} ;;
esac
[[ $folder == /* ]] || fail config "Not a full path: $folder (start it with / or ~/)"
[[ -d $folder ]] || fail notFound "No such folder: $folder"
folder=${folder:a}
# The folder in the button's words: a found one says where it came from.
place=$folder
[[ -n $found_in ]] && place="$folder (the folder of $found_in)"

# Where each tool may be installed.
claude_bins() {
  reply=( $HOME/.local/bin/claude(N-*) $HOME/.claude/local/claude(N-*) /opt/homebrew/bin/claude(N-*)
          /usr/local/bin/claude(N-*) $HOME/.npm-global/bin/claude(N-*) $HOME/.bun/bin/claude(N-*) )
}
codex_bins() {
  reply=( /opt/homebrew/bin/codex(N-*) /usr/local/bin/codex(N-*) $HOME/.npm-global/bin/codex(N-*) $HOME/.bun/bin/codex(N-*)
          /Applications/ChatGPT.app/Contents/Resources/codex(N-*) /Applications/Codex.app/Contents/Resources/codex(N-*)
          $HOME/Applications/ChatGPT.app/Contents/Resources/codex(N-*) $HOME/Applications/Codex.app/Contents/Resources/codex(N-*) )
}

tool=${(L)tool}
if [[ -z $tool ]]; then
  claude_bins
  if (( $#reply )); then
    tool=claude
  else
    codex_bins
    (( $#reply )) || fail notFound "Neither Claude Code nor Codex is installed on this Mac (the claude or codex command)"
    tool=codex
  fi
fi
[[ $tool == (claude|codex) ]] ||
  fail config "Unknown tool \"$tool\": set tool=\"claude\" or tool=\"codex\" in this button’s settings"
terminal=${(L)terminal}
project_tmux=""
if [[ -z $terminal ]]; then
  session_terminal
  terminal=${REPLY:-terminal}                   # tmux, when the session ran in it, is asked below
fi
[[ $terminal == (terminal|iterm2|ghostty|tmux) ]] ||
  fail config "Unknown terminal \"$terminal\": set terminal= to terminal, iterm2, ghostty or tmux in this button’s settings"

# The session's worktree needs a repository: its marker, a folder or (in a worktree) a file, in the folder or above.
dir=$folder mark=.git  # not a call: the repository's own folder
until [[ -e $dir/$mark || $dir == / ]]; do dir=${dir:h}; done
[[ -e $dir/$mark ]] ||
  fail config "$place is not a Git repository: the agent works in a worktree of its own, so set a project folder that uses Git in this button’s settings"
# A found folder in a linked worktree (a session the button started works in one) stands for its main checkout: the
# new session makes a worktree of its own, never one inside another. The marker there is a file naming the main
# checkout's own: "<main>/<marker>/worktrees/<name>".
if [[ -n $found_in && -f $dir/$mark ]]; then
  line=$(head -n 1 -- "$dir/$mark" 2>/dev/null)
  line=${line#*: }
  [[ $line == /* ]] || line=$dir/$line
  if [[ $line == */$mark/worktrees/* ]]; then
    main=${${line%%/$mark/worktrees/*}:a}
    [[ -d $main/$mark ]] && folder=$main
  fi
fi

# Both tools make the worktree with git. A stock Mac has none: /usr/bin's copy is only a stub that opens an install
# dialog without the Command Line Tools — on a Mac nobody may be sitting at. So git is looked for in the developer
# folder xcode-select names, and without it the button says what to install.
dev=$(xcode-select -p 2>/dev/null)
vcs=( ${dev:+$dev/usr/bin/git(N-*)} )
(( $#vcs )) || fail notFound "This needs Apple’s Command Line Tools: install them in Terminal with xcode-select --install"

task=${DESMAPTIC_INPUT//$'\r'/}
task=${${task##[[:space:]]#}%%[[:space:]]#}
[[ -n $task ]] || fail other "Nothing to do: the task is empty"

tmp=$(mktemp -d) || fail other "No room for a temporary folder"

# ---- the tool: one that can make its own worktree ----
case $tool in
  (claude) claude_bins; name="Claude Code" ;;
  (codex)  codex_bins; name="Codex" ;;
esac
bin=( $reply )
(( $#bin )) || fail notFound "$name is not installed on this Mac (the $tool command)"
bin=$bin[1]
# Asked in a clean environment (no token of the agent's in it), with the usual places of node first for an npm install.
limited 8 env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} \
  PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH" $bin --help
case $? in
  (0) [[ $(<$tmp/out) == *--worktree* ]] ||
        fail other "This $name is too old to start in a worktree of its own: update it, then tap again" ;;
  (124) fail timeout "$name did not answer in 8 seconds" ;;
  (*) fail other "$name does not start: $(first_line $tmp/err)" ;;
esac

# A client in a clean environment talks to the account's default tmux server.
mux=( /opt/homebrew/bin/tmux(N-*) /usr/local/bin/tmux(N-*) )
(( $#mux )) &&
  tm=( env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH=$PATH LANG=en_US.UTF-8 $mux[1] -u )
# The session the default came from ran in tmux: a new window there while that server still runs — never a new
# session of a server nobody looks at; else the session's app.
[[ -n $project_tmux ]] && (( $#mux )) && limited 5 $tm list-sessions && terminal=tmux
[[ $terminal == tmux ]] && (( ! $#mux )) &&
  fail notFound "tmux is not installed on this Mac: install it with brew install tmux, or set another terminal in this button’s settings"

# ---- the session's folder: the task and the script typed into the new shell ----
# Under the account's own temporary folder, readable by it alone; the script deletes the folder before the tool
# starts. Folders of taps whose shell never ran it (a window closed at once) go after a day.
base=${${TMPDIR:-/tmp}%/}
rm -rf -- $base/desmaptic-task.*(N/mh+24)
run=$(mktemp -d "$base/desmaptic-task.XXXXXX") || fail other "No room for a temporary folder"
# The path is typed into a shell in single quotes: no character there may need more.
[[ $run == [[:alnum:]/._-]## ]] || fail other "The temporary folder’s path has unusual characters: $run"
print -r -- "$task" > "$run/task.txt" || fail other "No room for the task in $run"

strftime -s stamp '%y%m%d-%H%M%S' $EPOCHSECONDS
{
  print -r -- "folder=${(qq)folder} tool=${(qq)tool} bin=${(qq)bin} tree=task-$stamp run=${(qq)run}"
  cat <<'START'
task=$(<$run/task.txt)
rm -rf -- "$run"
cd -- "$folder" || exit 1
# Every push goes to a remote that does not exist: an empty pushInsteadOf matches every URL. Commits and fetches work.
export GIT_CONFIG_PARAMETERS="${GIT_CONFIG_PARAMETERS:+$GIT_CONFIG_PARAMETERS }'url.no-push-in-this-session::.pushInsteadOf='"
case $tool in
  (claude)
    exec $bin --worktree $tree --permission-mode acceptEdits \
      --append-system-prompt "This session was started from a phone; the task is its first message. Work in the current worktree, on its branch: commit there when the work is done. Never push, and leave other branches alone. Ask when you need a decision: the questions are answered from the phone." \
      --disallowedTools "Bash(git push:*)" "Bash(git push *)" -- "$task" ;;  # not a call: the denied command's text
  (codex)
    exec $bin --worktree --sandbox workspace-write --ask-for-approval on-request -- "$task" ;;
esac
START
} > "$run/start.zsh" || fail other "No room for the session’s script in $run"
typed="/bin/zsh -f '$run/start.zsh'"

# ---- the new shell ----
# For tmux, a new window of the server's current session, or, with no server running (only with terminal="tmux"
# set), a new session to attach to; the line is typed into the window's shell.
if [[ $terminal == tmux ]]; then
  if limited 5 $tm list-sessions; then
    limited 5 $tm new-window -P -F '#{pane_id}' -c "$folder" -n $tool
  else
    limited 5 $tm new-session -d -P -F '#{pane_id}' -c "$folder" -n $tool
  fi || fail other "tmux did not open a window: $(first_line $tmp/err)"
  pane=$(first_line $tmp/out)
  [[ $pane == %<-> ]] || fail other "tmux did not say which window it opened"
  limited 5 $tm send-keys -t $pane -l -- "$typed" && limited 5 $tm send-keys -t $pane Enter ||
    fail other "tmux did not take the typed line: $(first_line $tmp/err)"
  started
fi

# For the apps, their own AppleScript, started with Launch Services when they aren't running. Prints nothing, or
# "!<why not>". Arguments: the app (terminal, iterm2, ghostty), the folder, the line to type, 1 when just started.
case $terminal in
  (terminal) app=com.apple.Terminal appName=Terminal ;;
  (iterm2)   app=com.googlecode.iterm2 appName=iTerm2 ;;
  (ghostty)  app=com.mitchellh.ghostty appName=Ghostty ;;
esac
# Asked by bundle id, not with pgrep: `ghostty` is also the name of Ghostty's command-line tool.
pid=$(lsappinfo info -only pid -app $app 2>/dev/null)
pid=${pid##*=}
launched=0
if [[ $pid != <1-> ]]; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b $app || fail other "$appName did not start"
  launched=1
fi

read -r -d '' script <<'OSA'
on run argv
	set which to item 1 of argv
	set dir to item 2 of argv
	set typed to item 3 of argv
	set justStarted to (item 4 of argv is "1")
	with timeout of 20 seconds
		if which is "terminal" then
			if not (application id "com.apple.Terminal" is running) then return "!Terminal is not running"
			tell application id "com.apple.Terminal"
				set here to missing value
				if justStarted then
					-- Wait up to 3 s for the window Terminal opens at launch, and use it while it is the only one and idle.
					repeat 15 times
						if (count of windows) > 0 then exit repeat
						delay 0.2
					end repeat
					try
						if (count of windows) is 1 then
							set t to selected tab of window 1
							if not (busy of t) then set here to t
						end if
					end try
				end if
				if here is missing value then
					do script typed
				else
					do script typed in here
				end if
				activate
			end tell
		else if which is "iterm2" then
			if not (application id "com.googlecode.iterm2" is running) then return "!iTerm2 is not running"
			tell application id "com.googlecode.iterm2"
				if justStarted then
					repeat 15 times
						if (count of windows) > 0 then exit repeat
						delay 0.2
					end repeat
				end if
				set w to (create window with default profile)
				tell current session of w to write text typed
				activate
			end tell
		else
			if not (application id "com.mitchellh.ghostty" is running) then return "!Ghostty is not running"
			tell application id "com.mitchellh.ghostty"
				if justStarted then
					-- Wait up to 3 s for the window Ghostty opens at launch, so the tab joins it instead of a second window.
					repeat 15 times
						if (count of windows) > 0 then exit repeat
						delay 0.2
					end repeat
				end if
				set cfg to {initial working directory:dir, initial input:typed & linefeed}
				if (count of windows) > 0 then
					new tab in front window with configuration cfg
					activate
				else
					activate window (new window with configuration cfg)
				end if
			end tell
		end if
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" "$terminal" "$folder" "$typed" "$launched" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) fail permission "The agent may not control $appName: allow it in System Settings → Privacy & Security → Automation" ;;
    *-10004*|*macos-applescript*) fail config "Ghostty’s AppleScript is turned off: macos-applescript = false in its config" ;;
    *-1712*) fail timeout "$appName did not answer: a dialog may be waiting ($appName’s, or the macOS question about Automation)" ;;
    '!'*)    fail other "${answer#!}" ;;
    *)       fail other "$appName did not answer: ${answer##*execution error: }" ;;
  esac
fi
started
