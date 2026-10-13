# Proxyman › macOS Proxy, the live state: where the Mac's HTTP and HTTPS proxy settings send web traffic.
#   on (green)     — to this account's Proxyman: the proxy host is this Mac (127.x.x.x or ::1) and Proxyman listens
#                    on the port;
#   other (orange) — to a proxy on this Mac that is not this Proxyman: another tool, Proxyman in another account, or a
#                    port nobody listens on any more, when the apps that follow the setting cannot connect at all;
#   off            — no HTTP or HTTPS proxy on this Mac: the button's own grey look. A proxy on another computer (a
#                    company proxy) counts as none: it is not Proxyman's.
# `scutil --proxy` reads the settings in force; `lsof` tells whose port it is, and only when the settings or Proxyman's
# process change (or a minute has passed). No permission, no Apple event, nothing Proxyman notices, and Proxyman is
# never launched. Every 5 s while the button is on screen, every second for a few seconds after its long press (it
# leaves a file in the button's storage), and nothing is read while the button is off screen (a look at the phone
# every 5 s). A frame goes out only when the state changes: the button's colour and symbol, no words.
# The startup script is this file (app.json).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Proxyman macOS Proxy: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_rm || { print -u2 -- "Proxyman macOS Proxy: zsh module files is missing"; exit 1 }

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
dir=""
[[ -n $DESMAPTIC_STORAGE ]] && dir="$DESMAPTIC_STORAGE/gallery/$cell"   # "changed": the long press sent ToggleSystemProxy
period=5                                        # seconds between looks while the button is on screen
green="#30D158" orange="#FF9F0A"

# ports = the ports of the HTTP and HTTPS proxies that are this Mac, from the settings in force. 1 when scutil did
# not answer. scutil prints the top-level keys two spaces in; deeper lines (ExceptionsList's items, __SCOPED__'s
# per-interface copies) are skipped.
local_proxy_ports() {
  local out line key kind
  local -A value
  ports=()
  out=$(scutil --proxy 2>/dev/null) || return 1
  for line in ${(f)out}; do
    [[ $line == '  '[A-Za-z]*' : '* ]] || continue
    key=${${line%% : *}//[[:space:]]/}
    value[$key]=${line#* : }
  done
  for kind in HTTP HTTPS; do
    [[ ${value[${kind}Enable]} == 1 && ${value[${kind}Port]} == <-> ]] || continue
    [[ ${value[${kind}Proxy]} == (127.<->.<->.<->|::1) ]] && ports+=(${value[${kind}Port]})
  done
  ports=(${(u)ports})
  return 0
}

asked="" answer="" asked_at=0                   # what lsof was last asked (ports and Proxyman's processes), its answer

# REPLY = on, other, off, or keep (scutil did not answer: the phone keeps what it shows).
read_state() {
  local port
  local -a ports pids
  if ! local_proxy_ports; then REPLY=keep; return; fi
  if (( ! $#ports )); then REPLY=off; return; fi
  pids=(${(f)"$(pgrep -xU $UID Proxyman)"})
  if (( ! $#pids )); then REPLY=other; return; fi
  if [[ "$ports / $pids" != "$asked" ]] || (( EPOCHSECONDS - asked_at >= 60 )); then
    answer=on
    for port in $ports; do                      # by what it prints: its status is 1 when one of the pids is gone
      [[ -n $(lsof -nP -a -p ${(j:,:)pids} -iTCP:$port -sTCP:LISTEN -Fp 2>/dev/null) ]] || answer=other
    done
    asked="$ports / $pids" asked_at=$EPOCHSECONDS
  fi
  REPLY=$answer
}

# 0 when the phone shows the button, or when it cannot say (an older app).
visible() {
  local out code body
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

# post on|other|off → 0 when the agent took it. Off is the button's own look.
post() {
  local json out code
  case $1 in
    on)    json="{\"cellId\":\"$cell\",\"color\":\"$green\",\"icon\":\"network.badge.shield.half.filled\"}" ;;
    other) json="{\"cellId\":\"$cell\",\"color\":\"$orange\",\"icon\":\"exclamationmark.triangle\"}" ;;
    *)     json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Proxyman macOS Proxy: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

typeset -F next_at=0 quick_until=0
shown=""                                        # on, other or off as the phone shows it; "" before the first post
while true; do
  if [[ -n $dir && -e $dir/changed ]]; then     # a long press: look now, then every second for a moment —
    zf_rm -f $dir/changed 2>/dev/null           # Proxyman may take a few seconds to change the settings
    next_at=0 quick_until=$(( EPOCHREALTIME + 8 ))
  fi
  if (( EPOCHREALTIME >= next_at )); then
    (( next_at = EPOCHREALTIME + (EPOCHREALTIME < quick_until ? 1 : period) ))
    if visible; then
      read_state
      if [[ $REPLY != keep && $REPLY != "$shown" ]]; then
        if post $REPLY; then shown=$REPLY; else (( next_at = EPOCHREALTIME + 10 )); fi
      fi
    fi
  fi
  zselect -t 25                                 # a quarter of a second, without starting a process
done
