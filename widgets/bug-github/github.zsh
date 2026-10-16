# Bug on GitHub › the issue, through the GitHub CLI (`gh issue create`) in the project folder, after report.zsh
# (item.json):
#   "folder=\"\"   # ← …\n@file:report.zsh\n@file:github.zsh"
# The setting: folder — the project's repository on the Mac; the issue goes to its GitHub repository (gh's default
# one there), with its branch and last commit. While it is empty the button refuses and says where to set it. gh
# signs in by itself (gh auth login, once in Terminal): no key on the button. GitHub has no API for attaching a
# picture to an issue, so a screenshot goes onto the Mac's clipboard and the new issue opens in the browser, where
# ⌘V in a comment adds it.

[[ -n $folder ]] ||
  fail config "No project folder set: put it in this button’s settings, e.g. folder=\"~/Developer/my-app\""
expand_folder
gh=( /opt/homebrew/bin/gh(N-*) /usr/local/bin/gh(N-*) )
(( $#gh )) || fail notFound "The GitHub CLI is not installed: brew install gh, then gh auth login in Terminal"
version_control                                 # gh asks the version control tool which repository the folder is

read_report
call update-button "{\"cellId\":\"$cell\",\"icon\":\"hourglass\"}" >/dev/null
context
body=$description
[[ -n $extra ]] && body+=${body:+$'\n\n'}$'---\n'$extra
[[ -n $shot ]] && body+=$'\n'"- A screenshot of the simulator follows in a comment"
print -r -- "$body" > "$tmp/in"

# gh runs in a clean environment — the account's HOME, USER, LOGNAME and TMPDIR, and a PATH with the tool's folder
# first — so neither the agent's token, under any of its names, nor the typed text reaches it or what it starts. It
# never asks anything; the body comes from stdin.
cd -- "$folder" || fail permission "The folder cannot be opened: $folder"
limited 40 env -i HOME=$HOME USER=$USER LOGNAME=$LOGNAME ${TMPDIR:+TMPDIR=$TMPDIR} PATH="${vcs[1]:h}:$PATH" \
  GH_PROMPT_DISABLED=1 NO_COLOR=1 $gh[1] issue create --title "$title" --body-file -
case $? in
  (0) ;;
  (124) fail timeout "GitHub did not answer in 40 seconds" ;;
  (*) err=$(first_line $tmp/err)
      [[ $err == *(auth\ login|authenticat)* ]] && fail auth "The GitHub CLI is not signed in: run gh auth login in Terminal"
      [[ $err == *(no\ git\ remotes|not\ a\ git\ repository|could\ not\ determine)* ]] && # not a call: gh's error text
        fail config "$folder is not a GitHub repository: set the folder of one"
      fail other "gh issue create: ${err:-no answer}" ;;
esac
url=${${(f)"$(<$tmp/out)"}[(r)https://*]}
[[ -n $url ]] || fail other "GitHub did not say which issue it made"

if [[ -n $shot ]]; then
  result=$(osascript -l JavaScript -e '
ObjC.import("AppKit");
function run(argv) {
  const data = $.NSData.dataWithContentsOfFile(argv[0]);
  if (data.isNil()) return "unreadable";
  const board = $.NSPasteboard.generalPasteboard;
  board.clearContents;
  return board.setDataForType(data, $.NSPasteboardTypePNG) ? "ok" : "unwritable";
}' "$shot" 2>/dev/null)
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  [[ $result == ok ]] && env -i /usr/bin/open -- "$url"
fi
flash checkmark "#${url:t}"
exit 0
