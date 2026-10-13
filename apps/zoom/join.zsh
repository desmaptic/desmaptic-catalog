# Zoom › Join My Meeting: opens a meeting you join often — your Personal Meeting ID, a recurring meeting — by its ID
# and passcode, through Zoom's own join link handed to Zoom by Launch Services, as a link clicked in a browser is
# (zoommtg://zoom.us/join?confno=<ID>&pwd=<passcode>; the scheme is in Zoom's Info.plist, the route and its fields in
# its strings, Zoom 7.0.5). So it works outside a meeting and with Zoom in the background, needs no permission, and
# starts Zoom when it is closed. Zoom brings the meeting forward; in another meeting it asks whether to leave that one.
# The button's first line sets both (app.json), then this file:
#   "id=\"\"; pwd=\"\"   # ← …\n@file:join.zsh"
# Until the ID is set it refuses and says where to set it. The ID may be written with spaces or dashes, as Zoom shows
# it (123 456 7890); the passcode is sent percent-encoded, never pasted into the link as it is.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

id=${id//[[:space:]-]/}
if [[ -z $id ]]; then
  print -u2 -- "Set your meeting ID in the first line of this button's script"
  exit 1
fi
if [[ $id != <-> || ${#id} -lt 9 || ${#id} -gt 11 ]]; then
  print -u2 -- "The meeting ID is 9 to 11 digits, as Zoom shows it (123 456 7890)"
  exit 1
fi
if [[ $pwd == *[^[:graph:]]* || ${#pwd} -gt 64 ]]; then
  print -u2 -- "The passcode is letters, digits and signs, without spaces"
  exit 1
fi

# The passcode, percent-encoded: everything but letters, digits and - . _ ~ (one byte each: only printable ASCII is let in).
code=""
for c in ${(s::)pwd}; do
  if [[ $c == [A-Za-z0-9._~-] ]]; then code+=$c; else code+=$(printf '%%%02X' "'$c"); fi
done

url="zoommtg://zoom.us/join?confno=$id"
[[ -n $code ]] && url+="&pwd=$code"
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open -b us.zoom.xos "$url" 2>/dev/null || { print -u2 -- "Zoom did not open the meeting: is Zoom installed?"; exit 1 }
