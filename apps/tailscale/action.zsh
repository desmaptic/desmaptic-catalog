# Tailscale › every press of the page: what it does is the action on the command's first line, then ts.zsh and this
# file (app.json):
#   "action=down\n@file:ts.zsh\n@file:action.zsh"
#
#   up         turns Tailscale on (`tailscale up` with no flags: it keeps every setting and only connects again),
#              letting the Mac reach the local network first (keep_lan); opens the app first when it is closed.
#              Signed out, it refuses: signing in happens in the app.
#   down       turns Tailscale off (`tailscale down`) — not while the phone reaches the Mac through Tailscale (guard,
#              ts.zsh): off, the phone could never reach the Mac again to turn it back on. When the organization asks
#              for a reason, or keeps Tailscale always on, it says so: no reason is made up for the user.
#   exit-on    sends the Mac's traffic through the exit node set in the button ($node; empty: the best one Tailscale
#              picks, auto:any), keeping the local network reachable, so a phone on the same Wi-Fi still connects.
#   exit-off   sends it out directly again.
#   account    shows on the button which account (tailnet) is in use.
#   switch     switches to the account set in the button ($account: its tailnet, e-mail, nickname or id; empty: the
#              next signed-in one) — not while the phone reaches the Mac through Tailscale, as down; then lets the
#              Mac reach the local network (keep_lan).
#   netcheck   checks the Mac's connection the way Tailscale sees it: the button shows the nearest relay and its
#              latency (green — direct connections work, orange — UDP is blocked and only relays carry the traffic),
#              and the phone gets the whole of it.
[[ $action == (up|down|exit-on|exit-off|account|switch|netcheck) ]] || fail config "Unknown action: ${action-none}"

need_cli

# ready: the status as it is now (not a loop's read), or the press ends with why it cannot be read.
ready() {
  status fresh || fail ${REPLY%% *} "${REPLY#* }"
}

# keep_lan: lets the Mac reach its local network while an exit node is in use — Tailscale's default is not to.
# Tailscale keeps a chosen exit node through off and on, and each account has its own: without this, turning
# Tailscale on or switching accounts would send the agent's answers to a phone on the Wi-Fi into the tunnel, and the
# phone would lose the Mac. Without an exit node it changes nothing. `tailscale set` works while Tailscale is off.
keep_lan() {
  run_ts 15 set --exit-node-allow-lan-access=true
  local rc=$?
  (( rc == 0 )) || { ts_refusal $rc "tailscale set"; fail ${REPLY%% *} "${REPLY#* }"; }
}

# shorten <text>: REPLY = the text cut to fit a button's title.
shorten() {
  local LC_ALL=en_US.UTF-8
  REPLY=$1
  (( ${#REPLY} > 16 )) && REPLY="${REPLY[1,15]}…"
  return 0
}

# start_app: opens Tailscale in the background when it is closed, and waits until its service answers (15 s).
start_app() {
  app_running && return 0
  [[ -n $app ]] || return 0
  env -i /usr/bin/open -g -b $app || fail notRunning "Tailscale did not open: open it on the Mac"
  local deadline=$(( EPOCHSECONDS + 15 ))
  while (( EPOCHSECONDS < deadline )); do
    if app_running && status fresh; then return 0; fi
    sleep 1
  done
  fail timeout "Tailscale opened but didn’t answer in time: try again in a moment"
}

# accounts: reads the signed-in accounts into ids, names and current (the index of the one in use).
ids=() names=() keys=() current=0
accounts() {
  local rc row id name key selected
  run_ts 10 switch --list --json
  rc=$?
  if (( rc != 0 )); then ts_refusal $rc "tailscale switch --list"; fail ${REPLY%% *} "${REPLY#* }"; fi
  # one account a line: its id, whether it is in use, its tailnet (the name shown), then every name it goes by
  for row in "${(@f)$(jq -r '.[]? | [(.id // "" | tostring), (.selected // false | tostring), ((.tailnet // "") | if . == "" then "-" else . end),
      ([.id, .tailnet, .account, .nickname] | map(select(. != null and . != "") | tostring | ascii_downcase) | join("\t"))]
      | join("\t")' "$tmp/out" 2>/dev/null)}"; do
    IFS=$'\t' read -r id selected name key <<< "$row"
    [[ -n $id ]] || continue
    [[ $name == - ]] && name=$id
    ids+=( $id ) names+=( "$name" ) keys+=( $'\t'"$key"$'\t' )
    [[ $selected == true ]] && current=$#ids
  done
  (( $#ids )) || fail auth "No account is signed in to Tailscale: sign in from its menu on the Mac"
}

case $action in
  (up)
    start_app
    ready
    case $state in
      (Running|Starting) poke; exit 0 ;;
      (NeedsLogin)       fail auth "Tailscale is signed out: sign in from its menu on the Mac" ;;
      (NeedsMachineAuth) fail auth "This Mac waits for your tailnet admin to approve it in the admin console" ;;
    esac
    keep_lan                                    # a stored exit node comes back with it
    run_ts 30 up
    rc=$?
    (( rc == 0 )) || { ts_refusal $rc "tailscale up"; fail ${REPLY%% *} "${REPLY#* }"; }
    poke ;;

  (down)
    ready
    [[ $state == Stopped ]] && { poke; exit 0; }
    guard "turning Tailscale off"
    run_ts 20 down
    rc=$?
    (( rc == 0 )) || { ts_refusal $rc "tailscale down"; fail ${REPLY%% *} "${REPLY#* }"; }
    poke ;;

  (exit-on)
    ready
    [[ $state == Running ]] || fail other "Tailscale is off: turn it on first"
    [[ -z ${node-} && $exit_name != - ]] && { poke; exit 0; }   # one is in use already: auto:any would replace it
    if [[ -z ${node-} ]] && (( offers == 0 )); then
      fail notFound "No device in your tailnet offers to be an exit node: turn it on in that device’s Tailscale, then approve it in the admin console"
    fi
    run_ts 15 set "--exit-node=${node:-auto:any}" --exit-node-allow-lan-access=true
    rc=$?
    if (( rc != 0 )); then
      err=$(first_line $tmp/err)
      case $err in
        (*(not\ advertising|ambiguous|no\ node\ found|invalid\ value|unknown\ node)*)
          fail config "Tailscale can’t use “${node:-auto:any}” as the exit node: $err. Set another one in the button’s settings" ;;
      esac
      ts_refusal $rc "tailscale set"
      fail ${REPLY%% *} "${REPLY#* }"
    fi
    poke ;;

  (exit-off)
    ready
    run_ts 15 set --exit-node=
    rc=$?
    (( rc == 0 )) || { ts_refusal $rc "tailscale set"; fail ${REPLY%% *} "${REPLY#* }"; }
    poke ;;

  (account)
    ready
    accounts
    (( current )) || fail other "Tailscale didn’t say which account is in use"
    shorten "${names[current]}"
    flash 3 "#32D74B" person.crop.circle "$REPLY" ;;

  (switch)
    ready
    accounts
    target=0
    if [[ -n ${account-} ]]; then
      for (( i = 1; i <= $#ids; i++ )); do
        [[ $keys[i] == *$'\t'"${(L)account}"$'\t'* ]] && { target=$i; break }
      done
      (( target )) || fail config "No signed-in Tailscale account is “$account”: sign it in from Tailscale’s menu on the Mac, or change the button’s settings"
    else
      (( $#ids > 1 )) || fail config "Only one account is signed in to Tailscale: add another from its menu on the Mac"
      target=$(( current % $#ids + 1 ))
    fi
    shorten "${names[target]}"
    title=$REPLY
    if (( target != current )); then
      guard "switching accounts"
      run_ts 30 switch $ids[target]
      rc=$?
      (( rc == 0 )) || { ts_refusal $rc "tailscale switch"; fail ${REPLY%% *} "${REPLY#* }"; }
      keep_lan                                  # the new account's own exit node, if it has one
    fi
    flash 3 "#32D74B" person.crop.circle.badge.checkmark "$title" ;;

  (netcheck)
    run_ts 30 netcheck
    rc=$?
    (( rc == 0 )) || { ts_refusal $rc "tailscale netcheck"; fail ${REPLY%% *} "${REPLY#* }"; }
    udp="" v4="" v6="" relay="" ms=""
    for line in "${(@f)$(<$tmp/out)}"; do
      line=${line##[[:space:]]#}
      case $line in
        ('* UDP: '*)           udp=${line#'* UDP: '} ;;
        ('* IPv4: '*)          v4=${line#'* IPv4: '} ;;
        ('* IPv6: '*)          v6=${line#'* IPv6: '} ;;
        ('* Nearest DERP: '*)  relay=${line#'* Nearest DERP: '} ;;
        (-\ *)                 # "- par: 51.8ms  (Paris)": the nearest relay's latency comes after its own line
          if [[ -z $ms && -n $relay && $line == (#b)-\ *:\ ([0-9.]##)ms\ #\((*)\) && $match[2] == "$relay" ]]; then
            printf -v ms %.0f $match[1]
          fi ;;
      esac
    done
    [[ -n $relay ]] || fail network "Tailscale reached none of its relay servers: check the Mac’s internet connection"
    mark() { [[ $1 == (true|yes*) ]] && print -n ✓ || print -n ✗; }
    report="UDP $(mark $udp) · IPv4 $(mark $v4) · IPv6 $(mark $v6) · $relay${ms:+ $ms ms}"
    call notify "$(jq -nc --arg c "$cell" --arg b "$report" '{title: "Tailscale", body: $b, targets: ["phone"], cellId: $c}')" >/dev/null
    shorten "$relay"
    if [[ $udp == true ]]; then colour="#32D74B" icon=checkmark.circle.fill; else colour="#FF9F0A" icon=tortoise.fill; fi
    flash 6 $colour $icon "$REPLY${ms:+ $ms ms}" ;;
esac
exit 0
