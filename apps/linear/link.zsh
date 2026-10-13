# Linear › Inbox, My Issues, Projects and Views, and Open Link, any page of Linear the user saved: a linear:// link,
# handed to Linear through Launch Services as a link clicked in a browser is. Linear runs it whatever the app in front,
# its shortcuts and the keyboard layout, and shows and focuses its window; nothing is typed or clicked, so no permission
# is needed. The four fixed links name no workspace: Linear adds the one it has open (the address is the user's own, so
# the page could not carry it). A closed Linear is opened: the page is what the button is for.
# Checked in Linear 1.32.4 (com.linear) by reading only. Info.plist declares no URL scheme; the app registers linear: as
# the default handler at launch (app.asar, out/main/index.js: setAsDefaultProtocolClient). Its open-url handler
# (resolveDeeplink) turns linear://<path> into https://linear.app/<path> and hands /<path> to the web client, which
# opens it in a Linear tab (a new one while Linear shows its tabs, the default); only /oauth/authorize goes to the
# browser instead (isForcedBrowserUrl). For the paths in the client's REDIRECTABLE_ROOT_PATHS (inbox, my-issues,
# projects, views…) it puts the open workspace in front: /inbox becomes /<workspace>/inbox (client build of 2026-09-27,
# redirects.js handleTopLevelRedirection). A new tab on every tap: the client reuses only a tab whose address equals the
# link's (DesktopNavigatorRouteHandler → addOrFocusTabFromPath), and the tab the last tap opened has moved on to
# /<workspace>/inbox. Linear's own Preferences › Auto-close stale tabs (never, by default) clears them.
# Open Link takes the page's address as Linear's Copy link gives it (https://linear.app/<workspace>/…: a team's cycle,
# a view, a project) and hands its path as linear://<path>. Until the link is set the button refuses and says where to
# set it; a character a link must not hold as it is (a space, a quote) is percent-encoded.
# Every button's command is one line that names the page, then this file (app.json):
#   "action=inbox\n@file:link.zsh"   — inbox, my-issues, projects or views;
#   "link=\"\"   # ← …\naction=link\n@file:link.zsh"   — Open Link, its setting on the first line.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
case $action in
  inbox)     target='inbox' ;;                  # Inbox, as G then I
  my-issues) target='my-issues' ;;              # My issues, as G then M
  projects)  target='projects' ;;               # Projects, as G then P
  views)     target='views' ;;                  # Views
  link)      target='' ;;                       # the page the user saved, below
  *) print -u2 -- "Linear: unknown page \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [[ $action == link ]]; then
  link=${${link##[[:space:]]##}%%[[:space:]]##}
  [[ -n $link ]] ||
    { print -u2 -- "Set the link of a Linear page in the first line of this button's script"; exit 1 }
  rest=${${link#(#i)http(s|)://}#(#i)linear.app/}
  if [[ $rest == $link || $rest == ${link#(#i)http(s|)://} || -z $rest ]]; then
    print -u2 -- "This is not a link to a Linear page: it starts with https://linear.app/"
    exit 1
  fi
  (( ${#rest} <= 4000 )) || { print -u2 -- "The link is too long"; exit 1 }
  # Percent-encode what a link may not hold as it is; a % already there stays (Linear's links are encoded already).
  for c in ${(s::)rest}; do
    if [[ $c == [A-Za-z0-9._~:/?#@!\$\&\'\(\)*+,\;=%-] ]]; then target+=$c; else target+=$(printf '%%%02X' "'$c"); fi
  done
fi

# -b: to Linear itself, not to whatever else may have claimed linear:// links, and even before Linear has claimed them
# (it does so only when it runs).
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.linear "linear://$target" || { print -u2 -- "Linear did not take the link"; exit 1 }
exit 0
