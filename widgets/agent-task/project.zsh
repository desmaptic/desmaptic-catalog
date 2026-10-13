# The project folder when the button's folder setting is empty — shared, word for word, by Ask the Project
# (widgets/ask-project/) and Task for an Agent (widgets/agent-task/); a fix goes into both copies. Functions only:
# the tap script after this file calls them. The button's command (item.json):
#   "folder=\"\"   # ← …\n@file:project.zsh\n@file:ask.zsh"
#
# project_folder: in order —
#   1. the folder of the most recent Claude Code or Codex session that the Desmaptic plugin recorded and that still
#      runs. A record (AISessions/<session>.json, written by the plugin's hook) names only the folder: the path is the
#      working folder of the session's own process (lsof) — the process the record's address names when there is one,
#      or a claude / codex process of this account working in a folder of that name. A run without a person at it
#      (claude -p, codex exec, Codex's app server) does not count;
#   2. with no such session, the folder of the front window of Terminal, iTerm2, Ghostty or Finder — whichever of them
#      is in front of the others in the Mac's window order and has a window. Only that window counts: when its folder
#      can't be read, or is the home folder or /, the button refuses rather than take a window behind it. A folder
#      inside a project (~/Developer/my-app/src) stands for the project: the nearest folder above it, below the home
#      folder, that is under version control. Read through the app's own AppleScript: the first time macOS asks
#      whether the agent may control it.
# Sets folder (a full path) and found_in (where it came from, for the button's words) and returns 0; returns 1 when
# nothing was found; returns 2 when the front window gave no project — project_why says why, project_kind is the
# /api/error kind.
#
# session_terminal: the terminal of the session the folder came from — or, when it came from elsewhere, of the most
# recent plugin session — in REPLY: terminal (Terminal), iterm2 or ghostty, the app it ran in; "" when it is none of
# them. project_tmux is 1 when that session ran in tmux on the server a client started without settings talks to
# (whether the server still runs is the tap script's to ask).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)

project_store="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/AISessions"

# The plugin's session records, newest first, as "<updated> <session> <tool>" lines in project_records (closed
# sessions left out).
project_records() {
  local f j tool
  local -a lines
  typeset -ga project_list
  for f in $project_store/*.json(N.); do
    [[ ${f:t:r} =~ '^[A-Za-z0-9_-]{1,128}$' && -r $f ]] || continue
    j=$(<$f)
    [[ $j =~ '"tool":"(claude|codex)"' ]] || continue
    tool=$match[1]
    [[ $j =~ '"state":"([a-z]+)"' && $match[1] != closed ]] || continue
    [[ $j =~ '"updated":([0-9]+)' ]] || continue
    lines+=( "$match[1] ${f:t:r} $tool" )
  done
  project_list=( ${(On)lines} )
}

# record_field <session> <key>: a string field of the session's record (or of its address, with key .addr:<key>), in
# REPLY, its escapes undone.
record_field() {
  local file=$project_store/$1.json key=$2
  [[ $key == .addr:* ]] && file=$project_store/$1.addr key=${key#.addr:}
  REPLY=""
  [[ -r $file ]] || return 1
  local j=$(<$file)
  [[ $j =~ "\"$key\":\"(([^\"\\\\]|\\\\.)*)\"" ]] || return 1
  REPLY=${match[1]//\\\"/\"}
  REPLY=${REPLY//\\\\/\\}
}

# This account's Claude Code and Codex processes that a person works in, with their working folders:
# project_tool[pid] = claude | codex, project_cwd[pid] = the folder.
project_processes() {
  typeset -gA project_tool project_cwd
  project_tool=() project_cwd=()
  local line pid name
  local -a w
  for line in ${(f)"$(ps -U $UID -o pid=,args= 2>/dev/null)"}; do
    w=( ${=line} )
    pid=$w[1] name=${w[2]:t}
    [[ $pid == <-> ]] || continue
    # Claude Code installed with npm runs as `node <…>/claude` until it renames itself.
    [[ $name == node ]] && name=${w[3]:t} && w[2]=()
    # The options only: what follows "--" is a first message, compared with nothing and never kept.
    w=( "${(@)w[1,${w[(i)--]}-1]}" )
    [[ $name == (claude|codex) ]] || continue
    if [[ $name == claude ]]; then
      (( ${w[(Ie)-p]} || ${w[(Ie)--print]} )) && continue
    else
      [[ ${w[3]:-} == (exec|e|app-server|mcp-server) ]] && continue
    fi
    project_tool[$pid]=$name
  done
  (( ${#project_tool} )) || return 1
  local p=""
  for line in ${(f)"$(lsof -a -w -d cwd -p ${(j:,:)${(k)project_tool}} -Fpn 2>/dev/null)"}; do
    case $line in
      (p<->) p=${line#p} ;;
      (n/*)  [[ -n $p ]] && project_cwd[$p]=${line#n} ;;
    esac
  done
  (( ${#project_cwd} ))
}

# named <folder> <name>: the folder, or the nearest folder above it with that name, in REPLY; 1 when none is named so.
named() {
  local d=$1
  while [[ $d != / && -n $d ]]; do
    [[ ${d:t} == $2 ]] && { REPLY=$d; return 0 }
    d=${d:h}
  done
  return 1
}

# The folder of the newest recorded session whose process runs → folder, found_in, project_sid.
session_folder() {
  local entry sid tool project pid
  local -a w
  project_records
  (( $#project_list )) || return 1
  project_processes || return 1
  for entry in $project_list; do
    w=( ${=entry} )
    sid=$w[2] tool=$w[3]
    record_field $sid project; project=$REPLY
    # The process the address names, while it still runs this tool; the record's folder, or one above its folder.
    if record_field $sid .addr:pid && [[ $REPLY == <-> && $project_tool[$REPLY] == $tool && -n $project_cwd[$REPLY] ]]; then
      pid=$REPLY
      if [[ -n $project ]] && named $project_cwd[$pid] $project; then folder=$REPLY; else folder=$project_cwd[$pid]; fi
    else
      [[ -n $project ]] || continue
      folder=""
      for pid in ${(k)project_tool}; do
        [[ $project_tool[$pid] == $tool && -n $project_cwd[$pid] ]] || continue
        named $project_cwd[$pid] $project && { folder=$REPLY; break }
      done
      [[ -n $folder ]] || continue
    fi
    [[ -d $folder && $folder != (/|$HOME) ]] || continue
    if [[ $tool == claude ]]; then found_in="the last Claude Code session"; else found_in="the last Codex session"; fi
    project_sid=$sid
    return 0
  done
  return 1
}

# tty_folder <device>: the working folder of what the terminal runs in front (the command, or the shell at its
# prompt), else of its shell (the child of login), in REPLY. This account's processes only.
tty_folder() {
  local pid
  local -a pids
  REPLY=""
  [[ $1 == ttys<-> ]] || return 1
  pids=( ${(f)"$(ps -t $1 -o pid=,ppid=,pgid=,tpgid=,uid=,comm= 2>/dev/null | awk -v me="$UID" '
      { pid[NR] = $1; ppid[NR] = $2; uid[NR] = $5; name[$1] = $6
        if ($1 == $3 && $3 == $4 && $5 == me) front = $1 }
      END {
        if (front != "") print front
        for (i = 1; i <= NR; i++) if (uid[i] == me && name[ppid[i]] ~ /(^|\/)login$/) { print pid[i]; exit }
      }')"} )
  for pid in $pids; do
    REPLY=$(lsof -a -w -p $pid -d cwd -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2); exit }')
    [[ $REPLY == /* && -d $REPLY ]] && return 0
  done
  REPLY=""
  return 1
}

# The front window of the terminal or Finder in front of the others → folder, found_in.
window_folder() {
  local asn app name answer d mark=.git  # not a call: the repository's own folder
  local -A app_of
  for app in com.apple.Terminal com.googlecode.iterm2 com.mitchellh.ghostty com.apple.finder; do
    for asn in ${(f)"$(lsappinfo find bundleid=$app 2>/dev/null)"}; do
      asn=${asn%%-\"*}
      [[ $asn == ASN:* ]] && app_of[$asn]=$app
    done
  done
  (( ${#app_of} )) || return 1

  # Each prints the window's folder, or its terminal device ("/dev/ttys003"), "-" when the app has no window to
  # read, or "!<why not>". One script per app: a script naming the terms of an app that is not installed does not
  # compile.
  local -A osa
  read -r -d '' 'osa[com.apple.Terminal]' <<'OSA'
on run argv
	if not (application id "com.apple.Terminal" is running) then return "-"
	with timeout of 10 seconds
		tell application id "com.apple.Terminal"
			repeat with w in windows
				try
					return tty of selected tab of w
				end try
			end repeat
		end tell
	end timeout
	return "-"
end run
OSA
  read -r -d '' 'osa[com.googlecode.iterm2]' <<'OSA'
on run argv
	if not (application id "com.googlecode.iterm2" is running) then return "-"
	with timeout of 10 seconds
		tell application id "com.googlecode.iterm2"
			set w to missing value
			try
				set w to current window
			end try
			if w is missing value then return "-"
			try
				return tty of current session of w
			end try
		end tell
	end timeout
	return "-"
end run
OSA
  read -r -d '' 'osa[com.mitchellh.ghostty]' <<'OSA'
on run argv
	if not (application id "com.mitchellh.ghostty" is running) then return "-"
	with timeout of 10 seconds
		tell application id "com.mitchellh.ghostty"
			set w to missing value
			try
				set w to front window
			end try
			if w is missing value then return "-"
			set t to missing value
			try
				set t to focused terminal of selected tab of w
			end try
			if t is missing value then return "!Ghostty did not say which terminal is in front"
			return working directory of t
		end tell
	end timeout
end run
OSA
  read -r -d '' 'osa[com.apple.finder]' <<'OSA'
on run argv
	if not (application id "com.apple.finder" is running) then return "-"
	with timeout of 10 seconds
		tell application id "com.apple.finder"
			if (count of Finder windows) is 0 then return "-"
			try
				return POSIX path of (target of Finder window 1 as alias)
			end try
		end tell
	end timeout
	return "-"
end run
OSA

  for asn in ${=$(lsappinfo visibleProcessList 2>/dev/null)}; do
    asn=${${asn%%-\"*}%:}
    app=${app_of[$asn]:-}
    [[ -n $app ]] || continue
    case $app in
      (com.apple.Terminal)    name=Terminal ;;
      (com.googlecode.iterm2) name=iTerm2 ;;
      (com.mitchellh.ghostty) name=Ghostty ;;
      (*)                     name=Finder ;;
    esac
    if ! answer=$(osascript -e "$osa[$app]" 2>&1) || [[ $answer == '!'* ]]; then
      project_kind=other
      case $answer in
        (*-1743*) project_kind=permission
                  project_why="The agent may not control $name to see its folder: allow it in System Settings → Privacy & Security → Automation" ;;
        (*-10004*|*macos-applescript*) project_kind=config
                  project_why="Ghostty’s AppleScript is turned off: macos-applescript = false in its config" ;;
        (*-1712*) project_kind=timeout
                  project_why="$name did not say its folder: macOS may be asking at the Mac whether the agent may control it" ;;
        ('!'*)    project_why=${answer#!} ;;
        (*)       project_why="$name did not say its folder: ${answer##*execution error: }" ;;
      esac
      return 2
    fi
    [[ $answer == - ]] && continue              # no window of it: the next app in the window order
    # This app's window is the one in front: its folder, or a refusal — never the window of an app behind it.
    project_kind=other
    if [[ $answer == /dev/* ]]; then
      tty_folder ${answer#/dev/} ||
        { project_why="Could not see which folder the front $name window is in"; return 2 }
      answer=$REPLY
    fi
    [[ $answer == /* && -d $answer ]] || { project_why="The front $name window did not say its folder"; return 2 }
    answer=${answer:A}
    project_kind=config
    [[ $answer == $HOME ]] &&
      { project_why="The front $name window is in your home folder, not in a project: open your project’s folder there"; return 2 }
    [[ $answer == / ]] &&
      { project_why="The front $name window is at the top of the disk (/), not in a project: open your project’s folder there"; return 2 }
    # A folder inside a project stands for the project: the nearest folder above it under version control.
    d=$answer
    while [[ $d != (/|$HOME) ]]; do
      [[ -e $d/$mark ]] && { answer=$d; break }
      d=${d:h}
    done
    folder=$answer found_in="the front $name window"
    return 0
  done
  return 1
}

project_folder() {
  folder="" found_in="" project_why="" project_kind="" project_sid=""
  session_folder && return 0
  window_folder
}

session_terminal() {
  local sid=${project_sid:-} default=/tmp/tmux-$UID/default
  REPLY="" project_tmux=""
  if [[ -z $sid ]]; then
    project_records
    (( $#project_list )) || return 1
    sid=${${(s: :)project_list[1]}[2]}
  fi
  # tmux on the default server only: a session on a server of another socket is out of the button's reach.
  if record_field $sid .addr:via && [[ $REPLY == tmux ]]; then
    record_field $sid .addr:tmux_socket
    [[ -z $REPLY || ${REPLY:A} == "${default:A}" ]] && project_tmux=1
  fi
  record_field $sid app
  case $REPLY in
    (com.apple.Terminal)    REPLY=terminal ;;
    (com.googlecode.iterm2) REPLY=iterm2 ;;
    (com.mitchellh.ghostty) REPLY=ghostty ;;
    (*)                     REPLY="" ;;
  esac
  [[ -n $REPLY || -n $project_tmux ]]
}
