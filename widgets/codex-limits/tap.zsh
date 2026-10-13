# Codex Limits (tap): asks the widget for fresh numbers — it leaves the time in gallery/{{CELL_ID}}/refresh,
# which the startup script watches — and brings ChatGPT to the front when it is running. Never launches it: the limits
# need no ChatGPT window, and a tap on a gauge should not open an app. The app is found by its bundle id through
# lsappinfo, as the ChatGPT page's buttons do (the classic ChatGPT app has an executable of the same name).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir

if [[ -n $DESMAPTIC_STORAGE ]]; then
  zf_mkdir -p "$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}" 2>/dev/null
  print -r -- $EPOCHSECONDS > "$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}/refresh" 2>/dev/null
fi

# lsappinfo prints "pid"=<n> for a running app and nothing at all for one that is not.
if [[ $(lsappinfo info -only pid -app com.openai.codex 2>/dev/null) == *'"pid"='<->* ]]; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.openai.codex || { print -u2 -- "ChatGPT did not come to the front"; exit 1 }
fi
exit 0
