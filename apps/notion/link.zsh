# Notion › New Page, Notion AI and Home: a notion:// link, handed to Notion through Launch Services as a link clicked in
# a browser is. Notion runs it whatever the keyboard layout or the app in front, and `open` brings it to the front;
# nothing is typed and no permission is needed. The links name no page and no workspace: Notion opens them in the tab
# of the window used last, in the workspace used last. It never launches Notion: `open` would, so the script checks
# first. Checked in Notion 7.35.1 (app.asar: open-url → handleProtocolUrl strips "notion://<host>" and loads the path in
# the active tab of the window used last) and its web client of 2026-09-27 (routes "new" — "Creates a new page … in the
# target space and redirects to it", with no space given the one used last —, "ai" — "Notion AI landing page featuring
# a new chat input" — and "home" — "Redirects to personal home page or root").
# Every button's command is one line that names its action, then this file (app.json):
#   "action=new\n@file:link.zsh"   — new, ai or home.
case $action in
  new)  route=/new ;;                           # a new page where Notion puts new pages, opened
  ai)   route=/ai ;;                            # Notion AI's own page, with a new chat
  home) route=/home ;;                          # Home of the workspace used last
  *) print -u2 -- "Notion: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not by process name: a web app saved from Safari as "Notion" is a "Notion" process too. lsappinfo asks
# this login session's Launch Services — the one `open` hands the link to — and prints nothing for an app not running.
[[ -n $(lsappinfo info -only pid -app notion.id 2>/dev/null) ]] || { print -u2 -- "Notion is not running"; exit 1 }

# -b: to Notion itself, not to whatever else may have claimed notion:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b notion.id "notion://www.notion.so$route" || { print -u2 -- "Notion did not take the link"; exit 1 }
exit 0
