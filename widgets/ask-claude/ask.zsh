#!/bin/zsh
# Ask Claude tap: the question typed on the phone ($DESMAPTIC_INPUT) opens as a new chat — in the Claude app when the
# Mac has it, otherwise on claude.ai in the default browser. The app gets the link its own "Ask Claude" service opens,
# claude://claude.ai/new?q=<question>&surface=chat (checked by reading Claude 2.31226.1); the browser gets the same page
# of claude.ai. Both go through Launch Services: nothing is typed or clicked, so no permission is needed, and a closed
# Claude starts. The question is percent-encoded as one value of the link, never put into code.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# fail <kind> <message>: the toast after the tap says why (/api/error), then the tap ends.
fail() {
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Ask Claude: $2"
  exit 1
}

[[ -n ${DESMAPTIC_INPUT//[[:space:]]/} ]] || fail other "Nothing to ask: the question is empty"

# jq reads the text as UTF-8 whatever the locale; @uri leaves only A–Z a–z 0–9 - _ . ~ unencoded.
q=$(print -rn -- "$DESMAPTIC_INPUT" | jq -Rrs '@uri') && [[ -n $q ]] || fail other "Could not put the question into a link"

# -b: to Claude itself, not to whatever else may have claimed claude:// links. It fails when the Mac has no Claude.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.anthropic.claudefordesktop "claude://claude.ai/new?q=$q&surface=chat" 2>/dev/null && exit 0
env -i /usr/bin/open "https://claude.ai/new?q=$q" 2>/dev/null ||
  fail other "Neither the Claude app nor the browser took the question"
exit 0
