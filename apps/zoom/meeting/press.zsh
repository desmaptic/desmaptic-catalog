# Zoom › the meeting buttons' taps and holds: an item of Zoom's Meeting or View menu, found by its identifier and pressed
# through the Accessibility API ($zoom_ax press, meeting/ax.zsh) — the same item Zoom's own shortcut runs, in every
# language and on every keyboard layout, with Zoom in the background: muting from another app leaves you in that app.
# Opening a panel (participants, chat), the share picker or the choice of audio brings Zoom forward, since they are only
# of use there. "show" brings the meeting window forward; "leave" does too and then closes it, so Zoom asks what to do —
# as when you close the window yourself (a host chooses between ending the meeting for all and leaving it). Outside a
# meeting every one refuses and says so; a greyed-out item (Share Screen while the host allows no sharing) refuses too,
# and so do Record while Zoom already records (its item would stop or pause the recording then) and Record under any
# title that does not start a recording (a participant's request to the host). Record brings Zoom forward when it has not
# started recording within a second: Zoom is asking or explaining something in a dialog then.
# "key" is for what no menu has — Raise Hand and the reactions: it brings the meeting window forward, waits up to a
# second for macOS to report Zoom in front, and only then presses Zoom's shortcut ($zoom_ax key, which checks once more
# with Zoom itself): on a page kept open over another app, the key never lands in that app. Zoom stays in front.
# No Apple event, so no Automation question; it needs the Accessibility Desmaptic Agent has, and never launches Zoom.
# After a menu press it leaves the time in $DESMAPTIC_STORAGE/gallery/zoom/poke, so the live buttons read Zoom at once.
# Every button's command is one line that names what it does, then ax.zsh, then this file (app.json):
#   "action=press item=onMuteAudio:\n@file:meeting/ax.zsh\n@file:meeting/press.zsh"
#   "action=show\n@file:meeting/ax.zsh\n@file:meeting/press.zsh"   — show or leave
#   "action=key key=raise-hand\n@file:meeting/ax.zsh\n@file:meeting/press.zsh"   — raise-hand, thumbs-up, clap, heart
emulate -R zsh
case $action in
  press)
    case $item in
      onMuteAudio:)          label='Meeting › Mute audio' ;;
      onMuteVideo:)          label='Meeting › Start video' ;;
      onShare:)              label='Meeting › Start share' ;;
      onSwitchViewMode:)     label='Meeting › Gallery view' ;;
      onSwitchFullscreen:)   label='Meeting › Fullscreen' ;;
      onSwitchMinimalVideo:) label='Meeting › Enter minimal view' ;;
      onCopyInviteLink:)     label='Meeting › Copy invite link' ;;
      onManageParticipants:) label='View › Show participants' ;;
      onChat:)               label='View › Show chat' ;;
      onCloudRecord:)        label='Meeting › Record to the cloud' ;;
      onLocalRecord:)        label='Meeting › Record to this computer' ;;
      *) print -u2 -- "Zoom: unknown menu item \"$item\""; exit 1 ;;
    esac ;;
  show|leave) label="Zoom's meeting window" ;;
  key)
    # Zoom's default shortcuts (Settings › Keyboard shortcuts): the character, its US key code, the modifiers.
    case $key in
      raise-hand) char=y code=16 mods=option ;;           # ⌥Y  Raise/lower hand
      thumbs-up)  char=5 code=23 mods=option,command ;;   # ⌥⌘5 Send meeting reaction [thumbs up]
      clap)       char=4 code=21 mods=option,command ;;   # ⌥⌘4 Send meeting reaction [clapping hands]
      heart)      char=6 code=22 mods=option,command ;;   # ⌥⌘6 Send meeting reaction [love/heart]
      *) print -u2 -- "Zoom: unknown shortcut \"$key\""; exit 1 ;;
    esac
    label="Zoom's meeting window" ;;
  *) print -u2 -- "Zoom: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect
zmodload -F zsh/files b:zf_mkdir b:zf_mv

# pgrep sees every account's processes; -U keeps it to this one, whose Zoom the Accessibility API reaches.
pgrep -xqU $UID zoom.us || { print -u2 -- "Zoom is not running"; exit 1 }

# zoom_in_front: 0 once macOS reports Zoom as the app in front, 1 when it has not within a second. lsappinfo names the
# front app 'ASN:0x0-0x2ca2ca:' and finds Zoom as 'ASN:0x0-0x2ca2ca-"zoom.us":' — about 5 ms a look, one every 50 ms.
zoom_in_front() {
  local zoom front
  typeset -F deadline=$(( EPOCHREALTIME + 1 ))
  zoom=$(lsappinfo find bundleid=us.zoom.xos 2>/dev/null)
  zoom=${${zoom%%$'\n'*}%%-\"*}
  [[ $zoom == ASN:* ]] || return 1
  while true; do
    front=$(lsappinfo front 2>/dev/null)
    [[ ${front%:} == "$zoom" ]] && return 0
    (( EPOCHREALTIME < deadline )) || return 1
    zselect -t 5
  done
}

if [[ $action == press ]]; then
  answer=$(osascript -l JavaScript -e "$zoom_ax" press "$item" 2>&1)
elif [[ $action == key ]]; then
  answer=$(osascript -l JavaScript -e "$zoom_ax" window show 2>&1)
  if [[ $answer == ok ]]; then
    if zoom_in_front; then
      answer=$(osascript -l JavaScript -e "$zoom_ax" key "$char" "$code" "$mods" 2>&1)
    else
      answer='!behind'
    fi
  fi
else
  answer=$(osascript -l JavaScript -e "$zoom_ax" window "$action" 2>&1)
fi
case $answer in
  ok)
    if [[ $action != key && -n $DESMAPTIC_STORAGE ]]; then   # a shortcut changes nothing the live buttons show
      shared="$DESMAPTIC_STORAGE/gallery/zoom"
      zf_mkdir -p $shared 2>/dev/null
      print -r -- $EPOCHREALTIME > $shared/poke.$$ 2>/dev/null && zf_mv -f $shared/poke.$$ $shared/poke 2>/dev/null
    fi
    exit 0 ;;
  '!closed')   print -u2 -- "Zoom is not running" ;;
  '!idle')     print -u2 -- "Zoom is not in a meeting" ;;
  '!missing')  print -ru2 -- "$label is not in Zoom's menus now" ;;
  '!greyed')   print -ru2 -- "$label is not available in Zoom now" ;;
  '!recording') print -u2 -- "Zoom is already recording this meeting" ;;
  '!norecord') print -ru2 -- "$label does not start a recording in Zoom now: as a participant, ask the host" ;;
  '!nowindow') print -u2 -- "Zoom's meeting window is not open" ;;
  '!behind')   print -u2 -- "Zoom's meeting window did not come forward" ;;
  '!ax')       print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
  '!busy')     print -u2 -- "Zoom did not answer" ;;
  *)           print -ru2 -- "Zoom did not respond: ${${answer##*execution error: }[1,200]}" ;;
esac
exit 1
