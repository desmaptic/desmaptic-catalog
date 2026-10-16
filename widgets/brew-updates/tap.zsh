# Homebrew updates, the tap: asks the live loop (startup.zsh) for brew upgrade, once the phone has had it confirmed
# with the button's reply ("Update all" in any of its languages). A tap script is stopped after 60 s, so it only
# leaves $dir/upgrade: the loop opens the upgrade in a Terminal window within a second and follows it on the
# face. It refuses, and says why, without that reply (a long press, an older phone, a text of one's own), without
# Homebrew and while an upgrade runs. The reply is matched here: change it in item.json only together with this list.
emulate -R zsh
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 1' TERM INT
cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"

confirmed() {   # the reply, trimmed, in any case
  local LC_ALL=en_US.UTF-8 text=$1
  text=${${text##[[:space:]]#}%%[[:space:]]#}
  [[ $text == (#i)(update all|alle aktualisieren|actualizar todo|tout mettre à jour|обновить всё|обновить все) ]]
}

if ! confirmed "$DESMAPTIC_INPUT"; then
  print -u2 -- "Homebrew updates: nothing updated: confirm with the reply on the phone"
  exit 1
fi
if [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
  print -u2 -- "Homebrew updates: Homebrew is not installed: see brew.sh to install it"
  exit 1
fi
if [[ -e $dir/running ]]; then
  print -u2 -- "Homebrew updates: brew upgrade is already running"
  exit 1
fi
mkdir -p -- "$dir" && : > "$dir/upgrade" || { print -u2 -- "Homebrew updates: cannot write $dir"; exit 1 }
