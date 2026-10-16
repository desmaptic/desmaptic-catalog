# Microsoft Teams › Join My Meeting: opens a meeting you join often — a daily stand-up — from the link in its invite,
# handed to Teams by Launch Services as Teams' own link (msteams:/l/meetup-join/…; the scheme is in Teams' Info.plist,
# the route in its strings, Teams 26043.2109.4484.3337). So it works with Teams in the background, needs no permission,
# and starts Teams when it is closed; Teams brings the meeting's join screen forward. The button's first line sets the
# link (app.json), then this file:
#   "link=\"\"   # ← …\n@file:join.zsh"
# Until it is set the button refuses and says where to set it. Only a full meeting link opens this way
# (https://teams.microsoft.com/l/meetup-join/…); a short one (teams.microsoft.com/meet/<number>?p=…) is refused in words.
# A character a link must not hold as it is (a space, a quote, a brace of an unencoded context) is percent-encoded.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
setopt extended_glob
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

link=${${link##[[:space:]]##}%%[[:space:]]##}
if [[ -z $link ]]; then
  print -u2 -- "Set your meeting’s link in this button’s settings"
  exit 1
fi
rest=${link#(#i)https://}
rest=${rest#(#i)teams.microsoft.com}
if [[ $rest == $link || $rest == ${link#(#i)https://} ]]; then
  print -u2 -- "This is not a Teams meeting link: it starts with https://teams.microsoft.com/l/meetup-join/"
  exit 1
fi
if [[ $rest == (#i)/meet/* ]]; then
  print -u2 -- "A short link (teams.microsoft.com/meet/…) does not open this way: use the full one, https://teams.microsoft.com/l/meetup-join/…"
  exit 1
fi
if [[ $rest != (#i)/l/meetup-join/?* ]]; then
  print -u2 -- "This is not a Teams meeting link: it starts with https://teams.microsoft.com/l/meetup-join/"
  exit 1
fi
if (( ${#rest} > 4000 )); then
  print -u2 -- "The meeting link is too long"
  exit 1
fi

# Percent-encode what a link may not hold as it is; a % already there stays (the invite's link is encoded already).
target=""
for c in ${(s::)rest}; do
  if [[ $c == [A-Za-z0-9._~:/?#@!\$\&\'\(\)*+,\;=%-] ]]; then target+=$c; else target+=$(printf '%%%02X' "'$c"); fi
done

# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b com.microsoft.teams2 "msteams:$target" 2>/dev/null ||
  { print -u2 -- "Teams did not open the meeting: is Microsoft Teams installed?"; exit 1 }
