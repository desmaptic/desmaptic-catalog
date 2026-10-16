# Discord › Mute and Deafen, the tap: Discord's own switch at the bottom left of its window, pressed through the
# Accessibility API (discord.zsh) — the same click the mouse makes, so Discord does exactly what its switch does, in
# whatever language it speaks, and without coming forward: muting from another app leaves you in that app. Every
# command is one line that names the switch, then discord.zsh and this file (app.json):
#   "action=mute\n@file:voice/discord.zsh\n@file:voice/press.zsh"   — mute or deafen.
# Refuses, with the phone shaking the button, while Discord is not running, while its window is closed (closed to the
# Dock: the switches live in the window), while it shows no switches (its settings open, still starting) and while
# Discord greys them out. After the press it writes what Discord shows then into the state the live buttons share, so
# both change at once (Mute while deafened undeafens you too). It never launches Discord, and needs Accessibility only:
# no Apple event, so no Automation question.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  mute)   label="Mute" ;;
  deafen) label="Deafen" ;;
  *) print -u2 -- "Discord: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Discord: zsh module files is missing"; exit 1 }

discord_pid || { print -u2 -- "Discord is not running"; exit 1 }
pid=$REPLY
discord_program
answer=$(/usr/bin/osascript -l JavaScript -e "$REPLY" press $pid $action 2>&1)
first=${answer%%$'\n'*}
if [[ $answer != *$'\n'* ]]; then rest=""; else rest=${answer#*$'\n'}; fi
case $first in
  '') ;;
  '!noax')   print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
  '!busy')   print -u2 -- "Discord did not answer" ;;
  '!closed') print -u2 -- "Discord's window is closed: open it from the Dock" ;;
  '!none')   print -ru2 -- "Discord shows no $label switch now (it is at the bottom left of its window)" ;;
  '!greyed') print -ru2 -- "Discord has grayed out $label now" ;;
  '!'*)      print -ru2 -- "Discord did not take the press (${first#!})" ;;
  *)         print -ru2 -- "Discord did not answer: ${${first##*execution error: }[1,200]}" ;;   # osascript failed
esac
[[ -z $first ]] || exit 1
# The state after the press, "<ms> ok <mute> <deafen> <visited>", for the live buttons.
if [[ -n $DESMAPTIC_STORAGE && $rest == <->' ok '* ]]; then
  discord_keep "$DESMAPTIC_STORAGE/gallery/discord" "${rest% *}"
fi
exit 0
