# Ruler, the long press: stop measuring, and take a copied size off the button early. The command is common.zsh
# and then this file (item.json); the loop (startup.zsh) sees the files gone and gives the button back its own face.
# Nothing to cancel is no failure: the button is where the user wanted it. The clipboard is left as it is.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/system || { print -u2 -- "ruler: zsh module system is missing"; exit 1 }
ruler_setup || exit 1

zf_mkdir -p -- $dir 2>/dev/null
{ : >> "$dir/lock" } 2>/dev/null
zsystem flock -t 5 "$dir/lock" 2>/dev/null
case $? in
  (0) ;;
  (2) print -u2 -- "ruler: a tap is still at work"; exit 1 ;;
  (*) print -u2 -- "ruler: cannot use its folder $dir"; exit 1 ;;
esac
zf_rm -f -- $anchor_file $result_file || { print -u2 -- "ruler: could not stop the measurement"; exit 1 }
exit 0
