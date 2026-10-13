# ChatGPT › New Chat, Work, Codex (taps) and Settings: ChatGPT's own codex:// link, handed to ChatGPT through Launch
# Services as a link clicked in a browser is. ChatGPT runs it whatever the app in front, its shortcuts and the keyboard
# layout, and `open` brings it to the front; nothing is typed or clicked, so no permission is needed.
# Checked in ChatGPT 26.915.31945 (com.openai.codex, build 9922) by reading only: Info.plist registers codex:, and the
# app's own link parser (app.asar, .vite/build/bootstrap-*.js) routes codex://new?mode=chat|work|codex to a new chat in
# that mode with the cursor in the message box (the modes of its Chat | Work toggle and ChatGPT | Codex switch), and
# codex://settings to its settings page.
# The three new-chat links open ChatGPT when it is closed (the button's point: a new chat), Settings does not.
# The app is found by its bundle id through lsappinfo, not pgrep by name: the classic ChatGPT app (com.openai.chat) has
# an executable of the same name, and lsappinfo sees only this account's apps.
# Every button's command is one line that names the link, then this file (app.json):
#   "action=chat\n@file:link.zsh"   — chat, work, codex or settings.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  chat)     link='codex://new?mode=chat';  launch=1 ;;    # File › New Chat (⌘N), in Chat
  work)     link='codex://new?mode=work';  launch=1 ;;    # the same, in Work
  codex)    link='codex://new?mode=codex'; launch=1 ;;    # the same, in Codex
  settings) link='codex://settings';       launch=0 ;;    # ChatGPT › Settings… (⌘,)
  *) print -u2 -- "ChatGPT: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# lsappinfo prints "pid"=<n> for a running app and nothing at all for one that is not.
if (( ! launch )) && [[ $(lsappinfo info -only pid -app com.openai.codex 2>/dev/null) != *'"pid"='<->* ]]; then
  print -u2 -- "ChatGPT is not running"
  exit 1
fi

# -b: to ChatGPT itself, not to whatever else may have claimed codex:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.openai.codex "$link" || { print -u2 -- "ChatGPT did not take the link"; exit 1 }
exit 0
