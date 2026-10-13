# Notes › Read Later, the tap: the page in the current tab of the browser the user looked at last — Safari, Google Chrome
# or Arc, whichever of them is in front of the others in the Mac's window order — becomes a new note in the default
# folder: the page's title as the note's title, its address as a link below ($note_js page, then add_note —
# add/note.zsh). The front app need not be the browser: on the Notes page, Notes itself is in front. Nothing is typed
# into the browser, no browser is launched, and it stays where it is. The browser part is the Reminders page's
# (apps/reminders/add/read-later.zsh), word for word.
# The tab is read through the browser's own AppleScript, so the first tap brings up the macOS question whether the agent
# may control Safari (or Chrome, or Arc), as well as the one about Notes. An incognito window of Chrome or Arc is
# refused — their dictionaries say which windows are incognito; Safari's does not say which windows are private, so a
# private Safari page is saved like any other. The address and the title reach $note_js in its environment, never on a
# command line. Silent when it worked; otherwise one line on stderr and the phone shakes the button. The command is:
#   "@file:add/note.zsh\n@file:add/read-later.zsh"
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# Which browser: lsappinfo lists this session's apps, the visible ones front to back — 'ASN:0x0-0x3efc2f84-"Arc":'.
# Only this account's browsers are asked about (lsappinfo speaks for this login session alone).
typeset -A browser_of
for id in com.apple.Safari com.google.Chrome company.thebrowser.Browser; do
  for asn in ${(f)"$(lsappinfo find bundleid=$id 2>/dev/null)"}; do
    asn=${asn%%-\"*}
    [[ $asn == ASN:* ]] && browser_of[$asn]=$id
  done
done
(( ${#browser_of} )) || { print -u2 -- "Read Later: open the page in Safari, Chrome or Arc first"; exit 1 }
browser=""
for asn in ${=$(lsappinfo visibleProcessList 2>/dev/null)}; do
  asn=${${asn%%-\"*}%:}
  if [[ -n ${browser_of[$asn]} ]]; then browser=${browser_of[$asn]}; break; fi
done
[[ -n $browser ]] || { print -u2 -- "Read Later: no Safari, Chrome or Arc window is showing (a hidden browser does not count)"; exit 1 }

# Each prints "<address>\n<title>", or "!<why not>". The front window is the first browser window — Safari lists its
# Settings window, Chrome its DevTools windows among its windows too, and an Arc window whose Space has no tabs is still a
# browser window. Its current tab is the one read: when it can't be read, the button says so rather than falling through
# to a window behind it and saving a page the user isn't looking at.
case $browser in
  com.apple.Safari)
    name=Safari
    read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.apple.Safari" is running) then return "!Safari is not running"
	set pageURL to missing value
	set pageTitle to missing value
	set found to false
	with timeout of 10 seconds
		tell application id "com.apple.Safari"
			repeat with candidate in windows
				set tabCount to 0
				try
					set tabCount to count of tabs of candidate
				end try
				if tabCount > 0 then
					set found to true
					try
						set theTab to current tab of candidate
						set pageURL to URL of theTab
						set pageTitle to name of theTab
					end try
					exit repeat
				end if
			end repeat
		end tell
	end timeout
	if not found then return "!No Safari window is open"
	if pageURL is missing value then return "!The front Safari tab shows no web page"
	if pageTitle is missing value then set pageTitle to ""
	return pageURL & linefeed & pageTitle
end run
OSA
    ;;
  com.google.Chrome)
    name=Chrome
    read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.google.Chrome" is running) then return "!Chrome is not running"
	with timeout of 10 seconds
		tell application id "com.google.Chrome"
			repeat with candidate in windows
				try
					set pageURL to URL of active tab of candidate
				on error
					return "!The front Chrome window shows no page"
				end try
				if pageURL does not start with "devtools:" then
					try
						set windowMode to mode of candidate
					on error
						return "!Could not tell whether the front Chrome window is incognito"
					end try
					if windowMode is "incognito" then return "!The front Chrome window is incognito: its pages are not saved"
					set pageTitle to ""
					try
						set pageTitle to title of active tab of candidate
					end try
					if pageTitle is missing value then set pageTitle to ""
					return pageURL & linefeed & pageTitle
				end if
			end repeat
		end tell
	end timeout
	return "!No Chrome window is open"
end run
OSA
    ;;
  company.thebrowser.Browser)
    name=Arc
    read -r -d '' script <<'OSA'
on run argv
	if not (application id "company.thebrowser.Browser" is running) then return "!Arc is not running"
	with timeout of 10 seconds
		tell application id "company.thebrowser.Browser"
			repeat with candidate in windows
				set isBrowser to false
				try
					set isBrowser to ((count of tabs of candidate) > 0)
				end try
				if not isBrowser then
					try
						set isBrowser to ((active space of candidate) is not missing value)
					end try
				end if
				if isBrowser then
					try
						set isPrivate to incognito of candidate
					on error
						return "!Could not tell whether the front Arc window is incognito"
					end try
					if isPrivate then return "!The front Arc window is incognito: its pages are not saved"
					-- The tab is named in the same request each time ("… of active tab of candidate"): Arc 1.166 cannot
					-- resolve the reference it returns for "active tab" again (apps/arc/action.zsh).
					try
						set pageURL to URL of active tab of candidate
					on error
						return "!The front Arc window shows no page"
					end try
					set pageTitle to ""
					try
						set pageTitle to title of active tab of candidate
					end try
					if pageTitle is missing value then set pageTitle to ""
					return pageURL & linefeed & pageTitle
				end if
			end repeat
		end tell
	end timeout
	return "!No Arc window is open"
end run
OSA
    ;;
esac

if ! answer=$(/usr/bin/osascript -e "$script" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control $name: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "$name is not running" ;;
    *-1712*) print -u2 -- "$name did not answer" ;;
    '!'*)    print -ru2 -- "Read Later: ${answer#!}" ;;
    *)       print -ru2 -- "$name did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
url=${answer%%$'\n'*}
title=${answer#*$'\n'}
[[ $answer == *$'\n'* ]] || title=""
if [[ $url != http://* && $url != https://* ]]; then
  print -u2 -- "Read Later: the front $name tab shows no web page (only http and https pages are saved)"
  exit 1
fi

answer=$(DESMAPTIC_PAGE_URL=$url DESMAPTIC_PAGE_TITLE=$title /usr/bin/osascript -l JavaScript -e "$note_js" page 2>&1)
if [[ $answer != ok$'\n'* ]]; then
  note_refusal "$answer"
  exit 1
fi
add_note "${answer#ok$'\n'}" || exit 1
exit 0
