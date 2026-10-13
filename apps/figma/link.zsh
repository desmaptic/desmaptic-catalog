# Figma › New Design File (tap) and New FigJam Board (hold), and Open File, a file the user works on every day: a
# figma:// link, handed to Figma through Launch Services as a link clicked in a browser is. Figma runs it whatever the app
# in front, its shortcuts and the keyboard layout, and shows and focuses its window; nothing is typed or clicked, so no
# permission is needed. A closed Figma is opened: the file is what the button is for.
# Checked in Figma 126.2.10 (com.figma.Desktop) by reading only. Info.plist registers the figma: scheme; the app's
# open-url handler (app.asar, main.js) puts https://www.figma.com/ in place of figma:// and opens the address in a file
# tab of the last focused window. Its route list there: design/new and board/new (or jam) open a new, untitled file of
# that kind (isNewFile), in a new tab; file/<key>, design/<key>, board/<key> and slides/<key> — the key 22 to 128
# letters and digits — open that file, and a file already open in a tab of that window is brought forward there
# instead of a second tab (openFileTab → getTabWithPath).
# Open File takes the file's link as Figma's Share › Copy link gives it (https://www.figma.com/design/<key>/<name>, with
# ?node-id=… when a layer was selected). Until it is set the button refuses and says where to set it; a character a link
# must not hold as it is (a space, a quote) is percent-encoded.
# Every button's command is one line that names the action, then this file (app.json):
#   "action=new-design\n@file:link.zsh"   — new-design or new-board;
#   "link=\"\"   # ← …\naction=file\n@file:link.zsh"   — Open File, its setting on the first line.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
case $action in
  new-design) target='design/new' ;;            # a new design file
  new-board)  target='board/new' ;;             # a new FigJam board
  file)       target='' ;;                      # the file the user saved, below
  *) print -u2 -- "Figma: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

if [[ $action == file ]]; then
  link=${${link##[[:space:]]##}%%[[:space:]]##}
  [[ -n $link ]] ||
    { print -u2 -- "Set your file's Share link in the first line of this button's script"; exit 1 }
  rest=${${link#(#i)https://}#(#i)(www.|)figma.com/}
  # The route names are matched as Figma does, in lowercase; the key as it is.
  if [[ $rest == $link || $rest == ${link#(#i)https://} || $rest != (file|design|board|slides)/[0-9a-zA-Z](#c22,128)(|[/?#]*) ]]; then
    print -u2 -- "This is not a link to a Figma file: copy it with Share › Copy link (https://www.figma.com/design/…)"
    exit 1
  fi
  (( ${#rest} <= 4000 )) || { print -u2 -- "The link is too long"; exit 1 }
  # Percent-encode what a link may not hold as it is; a % already there stays (Figma's links are encoded already).
  for c in ${(s::)rest}; do
    if [[ $c == [A-Za-z0-9._~:/?#@!\$\&\'\(\)*+,\;=%-] ]]; then target+=$c; else target+=$(printf '%%%02X' "'$c"); fi
  done
fi

# -b: to Figma itself, not to whatever else may have claimed figma:// links.
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.figma.Desktop "figma://$target" || { print -u2 -- "Figma did not take the link"; exit 1 }
exit 0
