#!/bin/zsh
# Calendar tap: joins the call of the meeting on the widget; without a call link it opens Calendar
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# The widget keeps the link of the meeting it shows here ("settings" while it has no calendar access).
link=""
file="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}/link"
[[ -r $file ]] && IFS= read -r link < "$file"

# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
case $link in
  settings)           env -i /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars" ;;
  https://*|http://*) env -i /usr/bin/open "$link" ;;
  *)                  env -i /usr/bin/open -b com.apple.iCal ;;
esac
