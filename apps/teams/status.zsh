# Microsoft Teams › Status: sets your Teams status — Busy, Do not disturb, Be right back, Available — by running a
# shortcut of the Shortcuts app made with Teams' own action "Change Teams status" (SetPresenceIntent in Teams' App
# Intents: available, busy, doNotDisturb, brb, away, offline; Teams 26043.2109.4484.3337). Teams has no link and no
# menu item for it, and its status menu is in its web client. The action opens Teams when it runs (openAppWhenRun):
# Teams comes forward, and starts when it is closed. One shortcut per status; the button's first line names it
# (app.json), then this file — add the button again with another name for another status:
#   "shortcut=\"Teams Busy\"   # ← …\n@file:status.zsh"
# A name the Shortcuts app does not have is refused in words, with what to make. The shortcut runs through the
# `shortcuts` command, which needs no permission of the agent; it is stopped after 30 seconds.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Teams: zsh modules datetime/zselect are missing"; exit 1 }

shortcut=${${shortcut##[[:space:]]##}%%[[:space:]]##}
if [[ -z $shortcut ]]; then
  print -u2 -- "Set the name of your status shortcut in this button’s settings"
  exit 1
fi
if [[ $shortcut == *[[:cntrl:]]* ]]; then
  print -u2 -- "The shortcut's name is one line"
  exit 1
fi

names=$(shortcuts list 2>/dev/null) || { print -u2 -- "Shortcuts did not answer"; exit 1 }
if (( ! ${${(f)names}[(Ie)$shortcut]} )); then
  print -ru2 -- "No shortcut \"$shortcut\": make it in Shortcuts with Microsoft Teams’ \"Change Teams status\", or name yours in this button’s settings"
  exit 1
fi

shortcuts run -- "$shortcut" >/dev/null 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; exit 1' TERM INT HUP
typeset -F deadline=$(( EPOCHREALTIME + 30 ))
while kill -0 $pid 2>/dev/null; do
  if (( EPOCHREALTIME > deadline )); then
    kill $pid 2>/dev/null
    print -ru2 -- "The shortcut \"$shortcut\" did not finish in 30 seconds"
    exit 1
  fi
  zselect -t 10
done
wait $pid || { print -ru2 -- "The shortcut \"$shortcut\" did not run: open it in Shortcuts to see why"; exit 1 }
