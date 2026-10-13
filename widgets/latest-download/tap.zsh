#!/bin/zsh
# Latest Download tap: open the item added to Downloads last with its default app (a folder opens in Finder)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# ---- latest_download: identical in tap.zsh and hold.zsh ----
# REPLY = the path of the item added to Downloads last; otherwise prints why to stderr and fails.
# "Last" is Finder's Date Added (the creation date where a disk keeps none): browsers and unpacked
# archives often backdate the creation and modification dates to the server's, never this one.
# Skipped: hidden files (.DS_Store, .localized…), unfinished downloads (.download, .crdownload, .part…)
# and a file a browser is still writing beside its .part or .aria2 companion.
# The name comes back followed by "|", so a newline at its end survives $(…).
latest_download() {
  local dir=$HOME/Downloads out
  out=$(osascript -l JavaScript - "$dir" <<'JXA'
ObjC.import("Foundation")
function run(argv) {
  const unfinished = ["download", "crdownload", "part", "partial", "opdownload", "aria2", "fdmdownload", "!ut", "!qb"]
  const added = ObjC.unwrap($.NSURLAddedToDirectoryDateKey), created = ObjC.unwrap($.NSURLCreationDateKey)
  const keys = $([added, created]), error = $()
  const list = $.NSFileManager.defaultManager.contentsOfDirectoryAtURLIncludingPropertiesForKeysOptionsError(
    $.NSURL.fileURLWithPathIsDirectory(argv[0], true).URLByResolvingSymlinksInPath, keys, $.NSDirectoryEnumerationSkipsHiddenFiles, error)
  if (list.isNil()) return (error.code == $.NSFileReadNoPermissionError ? "denied" : "unreadable") + "\n|"
  // Every call across the bridge costs about 0.1 ms, so the names come over in one call.
  const urls = list.js, names = ObjC.deepUnwrap(list.valueForKey("lastPathComponent")), present = new Set(names)
  const extension = name => name.lastIndexOf(".") > 0 ? name.slice(name.lastIndexOf(".") + 1).toLowerCase() : ""
  let best = null, bestTime = -Infinity
  names.forEach((name, i) => {
    if (unfinished.includes(extension(name)) || present.has(name + ".part") || present.has(name + ".aria2")) return
    const values = ObjC.deepUnwrap(urls[i].resourceValuesForKeysError(keys, null)) || {}
    const date = values[added] || values[created], time = date ? date.getTime() : -Infinity
    if (best === null || time > bestTime) { best = name; bestTime = time }
  })
  return best === null ? "empty\n|" : "ok\n" + best + "|"
}
JXA
  ) || { print -u2 -- "latest-download: cannot list $dir"; return 1 }
  case ${out%%$'\n'*} in
    ok)     REPLY=$dir/${${out#*$'\n'}%|} ;;
    empty)  print -u2 -- "latest-download: no finished downloads in $dir"; return 1 ;;
    denied) print -u2 -- "latest-download: no access to $dir (System Settings > Privacy & Security > Files & Folders)"; return 1 ;;
    *)      print -u2 -- "latest-download: cannot read $dir"; return 1 ;;
  esac
}

# ---- tap ----
latest_download || exit 1
# env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
env -i /usr/bin/open "$REPLY" || exit 1
exit 0
