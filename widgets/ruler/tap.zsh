# Ruler, the tap. The command is common.zsh and then this file (item.json).
#   No measurement going: remember where the pointer is (the anchor); the loop (startup.zsh) starts showing the
#   distance to the pointer on the button.
#   A measurement going: copy the distance to the pointer now, "128×64", to the Mac's clipboard and leave it as the
#   result, which the loop shows on the button for a while. Refused, the measurement going on, while the pointer is
#   still on the first spot: a double tap would otherwise put "0×0" on the clipboard in place of what the user had.
# A refusal is exit 1 with one line on stderr: the phone shakes the button.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/system || { print -u2 -- "ruler: zsh module system is missing"; exit 1 }
ruler_setup || exit 1

# The tap and the long press run at the same time when both are pressed: one at a time on the files.
zf_mkdir -p -- $dir 2>/dev/null
{ : >> "$dir/lock" } 2>/dev/null
zsystem flock -t 5 "$dir/lock" 2>/dev/null
case $? in
  (0) ;;
  (2) print -u2 -- "ruler: the long press is still at work"; exit 1 ;;
  (*) print -u2 -- "ruler: cannot use its folder $dir"; exit 1 ;;
esac

if read_anchor; then
  # ---- the second tap: copy the size ----
  # The start point goes in as arguments (after --: a coordinate left of the main display is negative).
  # The size is written as text only; nothing on the clipboard is read, so macOS asks nothing.
  out=$(osascript -l JavaScript -e "$ruler_js"'
function run(argv) {
  const [ax, ay] = start(argv);
  const size = distance(ax, ay);
  if (size === "0 0") return "still";
  const [across, down] = size.split(" ");
  const board = $.NSPasteboard.generalPasteboard;
  board.clearContents;
  return board.setStringForType($(across + "\u00D7" + down), "public.utf8-plain-text") ? size : "unwritable";
}' -- ${=REPLY} 2>&1)
  case $out in
    (<->' '<->)
      put_file $result_file "$out $EPOCHSECONDS" ||
        { print -u2 -- "ruler: copied, but could not leave the result for the button"; exit 1 }
      zf_rm -f -- $anchor_file
      exit 0 ;;
    (still)
      print -u2 -- "ruler: the pointer is still on the first spot; move it, then tap again" ;;
    (unwritable)
      print -u2 -- "ruler: the clipboard did not take the size" ;;
    (*)
      print -u2 -- "ruler: could not read the pointer${out:+ (${out[1,200]})}" ;;
  esac
  exit 1
fi

# ---- the first tap: remember where the pointer is ----
out=$(osascript -l JavaScript -e "$ruler_js"'
function run() { return here(); }' 2>&1)
[[ $out == (|-)<->.<->' '(|-)<->.<-> ]] || { print -u2 -- "ruler: could not read the pointer${out:+ (${out[1,200]})}"; exit 1 }
put_file $anchor_file "$out $EPOCHSECONDS" || { print -u2 -- "ruler: could not remember the first spot"; exit 1 }
zf_rm -f -- $result_file                        # a size still shown from the last measurement gives way
exit 0
