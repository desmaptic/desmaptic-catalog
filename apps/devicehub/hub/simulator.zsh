# Device Hub › Open URL and Clean Status Bar: simctl commands for the simulator in Device Hub's front window, or every
# booted one when it shows none (booted_simulators, hub/booted.zsh). No window, no app in front: Device Hub may stay in
# the background, or not run at all; nothing is booted, erased or installed. A connected device is never touched.
#   openurl — opens the button's link in the simulator, as a tap on it there would: a custom scheme opens the app
#             that registered it, an https link the app that claims it (a universal link) or Safari.
#   bar     — 9:41, a full battery, Wi-Fi and cellular bars on the status bar, for screenshots; it stays until cleared,
#             the simulator restarts, or it is set again.
#   clear   — the status bar as it was: every override is removed.
# The button's lines come first, then ax.zsh, booted.zsh and this file (app.json) — for Open URL the first line is the
# link the user edits; while it is empty, the tap refuses and says what to write:
#   "url=\"\"   # ← …\naction=openurl\n@file:hub/ax.zsh\n@file:hub/booted.zsh\n@file:hub/simulator.zsh"
#   "action=bar\n@file:hub/ax.zsh\n@file:hub/booted.zsh\n@file:hub/simulator.zsh"
emulate -R zsh
case $action in
  openurl)
    [[ -n $url ]] || { print -u2 -- "Write the link in the first line of the button’s script: url=\"myapp://settings\""; exit 1 }
    [[ $url =~ '^[A-Za-z][A-Za-z0-9+.-]*:[^[:space:]]+$' ]] || { print -ru2 -- "Not a link: “${url[1,80]}”. Write it with its scheme, like myapp://settings"; exit 1 }
    doing="open the link on" ;;
  bar)   doing="set the status bar of" ;;
  clear) doing="clear the status bar of" ;;
  *) print -u2 -- "Device Hub: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

booted_simulators || exit 1

failed=0 took=0 first=""
for i in $chosen; do
  case $action in
    openurl) args=( openurl "$udids[i]" "$url" ) ;;
    bar)     args=( status_bar "$udids[i]" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3
                    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 ) ;;
    clear)   args=( status_bar "$udids[i]" clear ) ;;
  esac
  if err=$("$simctl" "${args[@]}" 2>&1 >/dev/null </dev/null); then
    (( took++ ))
  else
    (( failed++ ))
    case $err in
      *-10814*) err="no app there opens ${url%%:*}: links" ;;   # Launch Services: no app for the link
      *)        err=${${err%%$'\n'*}[1,160]:-no answer} ;;
    esac
    [[ -z $first ]] && first="$names[i]: $err"
  fi
done
# Sent to every booted simulator, one that cannot take it (an Apple Watch: no app for the link, no status bar to set)
# does not fail the tap while another one took it.
(( failed == 0 || took > 0 )) && exit 0
(( failed > 1 )) && first="$first (and $(( failed - 1 )) more)"
print -ru2 -- "Could not $doing $first"
exit 1
