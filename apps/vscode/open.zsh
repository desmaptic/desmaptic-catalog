# VS Code › Open Project and Agents Window, through Launch Services, which finds VS Code by its bundle id wherever it
# is installed. Open Project hands the folder or .code-workspace file over as a double click in Finder does (VS Code's
# Info.plist declares both): the running VS Code opens it in a new window, or brings forward the window that has it
# open already, and a closed one starts with it. Unlike a vscode://file link this asks nothing. Agents Window starts a
# second VS Code with --agents, as VS Code's own `code` does on a Mac (open -n -g -a <app> --args …): it hands the
# flag to the running VS Code and quits. Both work with VS Code in the background or closed; no permission is needed.
# Checked in VS Code 1.121.0: `code --help` — "--agents  Opens the agents window"; out/main.js — open-file takes a
# .code-workspace as a workspace and a folder as a folder.
# Not through `code`: it puts every variable of its environment on open's command line (--env K=V), where any
# process can read it, and VS Code gives that environment to the window's terminals, tasks and extensions — the
# agent's token and this script's PATH and LC_ALL included. `open` passes its own environment to an app it starts,
# so it runs with none: VS Code gets the account's ordinary one, as from the Dock, and reads the login shell's itself.
# Every button's command names its action on a line of its own, then this file (app.json); Open Project's first
# line is the project, which the user sets:
#   "folder=\"\"   # ← …\naction=open\n@file:open.zsh"
#   "action=agents\n@file:open.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

case $action in
  open)
    [[ -n $folder ]] || { print -u2 -- "Open Project: set your project in this button’s settings, such as folder=\"~/Projects/app\""; exit 1 }
    [[ $folder == '~/'* ]] && folder=$HOME/${folder#\~/}          # "~/…" in quotes is not expanded by zsh
    [[ $folder == /* ]] || { print -u2 -- "Open Project: the project must start with / or ~/"; exit 1 }
    # A folder, or a workspace file: any other file would only open in an editor tab.
    [[ -d $folder || ( -f $folder && $folder == *.code-workspace ) ]] ||
      { print -ru2 -- "Open Project: no folder or .code-workspace file at $folder"; exit 1 } ;;
  agents) ;;
  *) print -u2 -- "VS Code: unknown action \"$action\""; exit 1 ;;
esac

app=$(osascript -l JavaScript -e 'function run(argv) {
  ObjC.import("AppKit");
  const url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(argv[0]);
  return url.isNil() ? "" : url.path.js;
}' com.microsoft.VSCode 2>/dev/null)
[[ $app == /* ]] || { print -u2 -- "VS Code is not installed"; exit 1 }

if [[ $action == open ]]; then
  env -i /usr/bin/open -a "$app" "$folder" >/dev/null 2>&1 || { print -u2 -- "VS Code did not open the project"; exit 1 }
else
  env -i /usr/bin/open -n -g -a "$app" --args --agents >/dev/null 2>&1 ||
    { print -u2 -- "VS Code did not open the agents window"; exit 1 }
fi
exit 0
