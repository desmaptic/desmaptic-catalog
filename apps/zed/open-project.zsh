# Zed › Open Project, through Launch Services, which finds Zed by its bundle id wherever it is installed. The folder
# is handed over as a double click in Finder does (Zed's Info.plist declares folders): the running Zed opens it in a
# window, or brings forward the window that has it open already, and a closed one starts with it. It works with Zed
# in the background or closed, and no permission is needed.
# Not through Zed's own `cli`: it sends its whole environment with the request, and Zed makes that the project's
# environment ("using project environment variables from CLI") for terminals, tasks and language servers — the
# agent's token and this script's PATH and LC_ALL included. `open` passes its own environment to an app it starts,
# so it runs with none: Zed gets the account's ordinary one, as from the Dock, and reads the login shell's itself.
# Checked in Zed 1.23.2: Info.plist — public.folder; the zed binary — "using project environment variables from CLI".
# The button's command starts with the folder, which the user sets, then this file (app.json):
#   "folder=\"\"   # ← …\n@file:open-project.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ -n $folder ]] || { print -u2 -- "Open Project: set your project’s folder in this button’s settings, such as folder=\"~/Projects/app\""; exit 1 }
[[ $folder == '~/'* ]] && folder=$HOME/${folder#\~/}            # "~/…" in quotes is not expanded by zsh
[[ $folder == /* ]] || { print -u2 -- "Open Project: the folder must start with / or ~/"; exit 1 }
[[ -d $folder ]] || { print -ru2 -- "Open Project: no folder at $folder"; exit 1 }

app=$(osascript -l JavaScript -e 'function run(argv) {
  ObjC.import("AppKit");
  const url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(argv[0]);
  return url.isNil() ? "" : url.path.js;
}' dev.zed.Zed 2>/dev/null)
[[ $app == /* ]] || { print -u2 -- "Zed is not installed"; exit 1 }

env -i /usr/bin/open -a "$app" "$folder" >/dev/null 2>&1 || { print -u2 -- "Zed did not open the folder"; exit 1 }
exit 0
