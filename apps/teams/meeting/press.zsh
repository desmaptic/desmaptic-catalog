# Microsoft Teams › a meeting control pressed from the phone: Teams' own button in the meeting window, pressed through
# the Accessibility API (teams.zsh) — the same click the mouse makes, so Teams does exactly what its button does, in
# whatever language it speaks. Mic, Camera, Raise Hand and Leave do it without bringing Teams forward; Meeting brings
# the meeting window to the front, and Share does that first, since the Share tray asks what to share. Every command
# is one line that names the control, then teams.zsh and this file (app.json):
#   "action=mic\n@file:meeting/teams.zsh\n@file:meeting/press.zsh"   — mic, camera, hand, chat, people, share, unshare,
#   show or leave. Chat and People open their panel in the meeting window and bring it forward, to be read.
# Share presses only while you do not share (Teams' same button then stops sharing — that is Unshare, a long press).
# Refuses, with the phone shaking the button, while Teams is not running, outside a meeting, and while Teams greys the
# control out. After Mic or Camera it writes what Teams shows then into the state the live buttons share, so they
# change at once. It never launches Teams, and needs Accessibility only: no Apple event, so no Automation question.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
labels=""
case $action in
  mic)     id=microphone-button show=- ;;
  camera)  id=video-button show=- ;;
  hand)    id=raisehands-button show=- ;;
  chat)    id=chat-button show=show ;;
  people)  id=roster-button show=show ;;
  leave)   id=hangup-button show=- labels=leave ;;
  share)   id=share-button show=show labels=shareIdle ;;
  unshare) id=share-button show=- labels=shareStop ;;
  show)    id=- show=show ;;
  *) print -u2 -- "Teams: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Teams: zsh module files is missing"; exit 1 }

teams_pid || { print -u2 -- "Microsoft Teams is not running"; exit 1 }
pid=$REPLY
teams_program
answer=$(/usr/bin/osascript -l JavaScript -e "$REPLY" press $pid $id $show $labels 2>&1)
first=${answer%%$'\n'*}
if [[ $answer != *$'\n'* ]]; then rest=""; else rest=${answer#*$'\n'}; fi
if [[ $first == '!'* ]]; then
  print -ru2 -- "${first#!}"
  exit 1
fi
if [[ -n $first ]]; then                        # not the reader's answer: osascript itself failed
  print -ru2 -- "Microsoft Teams did not answer: ${${first##*execution error: }[1,200]}"
  exit 1
fi
# The state after the press, "<ms> meeting <mic> <camera> <visited>", for the live buttons.
if [[ -n $DESMAPTIC_STORAGE && $rest == <->' meeting '* ]]; then
  teams_keep "$DESMAPTIC_STORAGE/gallery/teams" "${rest% *}"
fi
exit 0
