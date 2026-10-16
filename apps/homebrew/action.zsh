# Homebrew › every press of the page: what it does is the action on the command's first line, then brew.zsh and this
# file (app.json):
#   "action=update\n@file:brew.zsh\n@file:action.zsh"
#
#   update            fetches Homebrew's package list (brew update), then shows how many packages are out of date.
#   cleanup-check     shows how much brew cleanup would free, removing nothing.
#   cleanup           removes old versions and old downloads (brew cleanup, without its autoremove: that has its own
#                     button), then shows how much it freed.
#   autoremove-check  shows how many formulae nothing needs any more, and names them on the phone; removes nothing.
#   autoremove        uninstalls those formulae (brew autoremove), then names them on the phone.
#   services          names every Homebrew service and how it is (brew services list) on the phone, and shows how
#                     many run.
#
# Upgrading the packages is the general widget brew-updates on the page (widgets/brew-updates): its tap asks first,
# runs brew upgrade in a Terminal window and leaves out the casks that ask for the Mac's password. This page keeps no
# upgrade of its own, so two upgrades never run at once.
[[ $action == (update|cleanup-check|cleanup|autoremove-check|autoremove|services) ]] ||
  fail config "Unknown action: ${action-none}"

need_brew

case $action in
  (update)
    run_brew 40 "brew update" update --quiet
    outdated
    if (( n )); then
      flash 4 "#FF9F0A" shippingbox.fill "$n"
    else
      flash 3 "#32D74B" checkmark.circle.fill "0"
    fi ;;

  (cleanup-check|cleanup)
    if [[ $action == cleanup-check ]]; then
      run_brew 50 "brew cleanup --dry-run" cleanup --dry-run
    else
      brewing=( ${brewing[1,-2]} HOMEBREW_NO_AUTOREMOVE=1 $brew )
      run_brew 50 "brew cleanup" cleanup
    fi
    size=""
    for line in "${(@f)$(<$tmp/out)}"; do
      [[ $line == (#b)*(would\ free|has\ freed)\ approximately\ ([0-9.]##[A-Z]#B)\ * ]] && size=$match[2]
    done
    if [[ -z $size ]]; then
      flash 3 "#32D74B" checkmark.circle.fill "0"
    elif [[ $action == cleanup-check ]]; then
      flash 4 "#0A84FF" trash "$size"
    else
      flash 4 "#32D74B" trash.fill "$size"
    fi ;;

  (autoremove-check|autoremove)
    if [[ $action == autoremove-check ]]; then
      run_brew 40 "brew autoremove --dry-run" autoremove --dry-run
      names=( ${(f)"$(names_after 'Would autoremove')"} )
      title="brew autoremove --dry-run"
    else
      run_brew 50 "brew autoremove" autoremove
      names=( ${(f)"$(names_after 'Autoremoving')"} )
      title="brew autoremove ✓"
    fi
    if (( $#names == 0 )); then
      flash 3 "#32D74B" checkmark.circle.fill "0"
      exit 0
    fi
    notify "$title" "${(F)names}"
    if [[ $action == autoremove-check ]]; then
      flash 4 "#0A84FF" shippingbox "$#names"
    else
      flash 4 "#32D74B" trash.fill "$#names"
    fi ;;

  (services)
    run_brew 20 "brew services list" services list --json
    rows=( ${(f)"$(jq -r '.[]? | [.name, (.status // "none"), (.exit_code // "" | tostring)] | join(" ")' $tmp/out 2>/dev/null)"} )
    if (( $#rows == 0 )); then
      flash 3 "#8E8E93" gearshape.2 "0"
      exit 0
    fi
    body=() running=0
    for row in $rows; do
      read -r name state code <<< "$row"
      case $state in
        (started)   mark=●; running=$(( running + 1 )) ;;
        (scheduled) mark=◷ ;;
        (error)     mark=✗ ;;
        (*)         mark=○ ;;
      esac
      body+=( "$mark $name" )
      [[ $state == error && -n $code ]] && body[-1]+=" ($code)"
      [[ $state == (started|scheduled|error|none|stopped) ]] || body[-1]+=" · $state"
    done
    notify "brew services" "${(F)body}"
    flash 4 "#30B0C7" gearshape.2.fill "$running/$#rows" ;;
esac
exit 0
