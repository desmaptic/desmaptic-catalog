# Device Hub › the menu buttons' taps and holds: an item of Device Hub's Controls or Device menu, found by its name and
# pressed through the Accessibility API ($hub_ax, hub/ax.zsh) — the item Device Hub's own shortcut runs, on every
# keyboard layout, for the device whose window Device Hub has in front. Those items work only with Device Hub in front
# (in the background they are greyed out), so a press brings Device Hub forward first, raising the window it last used;
# Device Hub stays in front. An item that is greyed out or missing there — no simulator or device window in front, a
# device that cannot do it (an Apple Watch does not turn) — is a refusal with the reason; the phone shakes the button.
# No Apple event, so no Automation question; it needs the Accessibility Desmaptic Agent has, and never launches Device
# Hub. Every button's command is one line that names the item, then ax.zsh, then this file (app.json):
#   "action=press menu=Controls item=Home\n@file:hub/ax.zsh\n@file:hub/press.zsh"
#   "action=press menu=Controls item='Record Screen|Stop Recording'\n…"           — either name, as Device Hub shows it
emulate -R zsh
case $action in
  press)
    [[ -n $menu && -n $item ]] || { print -u2 -- "Device Hub: the button names no menu item"; exit 1 }
    label="$menu › ${sub:+$sub › }${item%%|*}" ;;
  *) print -u2 -- "Device Hub: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id: lsappinfo prints the pid of this account's running Device Hub, nothing when there is none.
[[ $(lsappinfo info -only pid -app com.apple.dt.Devices 2>/dev/null) == *'"pid"='<1->* ]] || { print -u2 -- "Device Hub is not running"; exit 1 }

answer=$(osascript -l JavaScript -e "$hub_ax" press "$menu" "${sub:-}" "$item" 2>&1)
case $answer in
  ok) exit 0 ;;
  '!closed')  print -u2 -- "Device Hub is not running" ;;
  '!behind')  print -u2 -- "Device Hub did not come to the front" ;;
  '!missing') print -ru2 -- "Device Hub shows no $label now: no simulator or device window in front, or that device has none" ;;
  '!greyed')  print -ru2 -- "$label is not available in Device Hub now: bring a simulator or device window forward" ;;
  '!ax')      print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
  '!busy')    print -u2 -- "Device Hub did not answer" ;;
  *)          print -ru2 -- "Device Hub did not respond: ${${answer##*execution error: }[1,200]}" ;;
esac
exit 1
