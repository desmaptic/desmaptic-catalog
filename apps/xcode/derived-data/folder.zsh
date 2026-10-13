# Xcode › DerivedData: where the folder is and whether it may be emptied. Functions only — every script of the
# button starts with this file (app.json): the widget's loop (startup.zsh) and the tap and long press (action.zsh).
# Each function runs with zsh's own options (emulate -L): `zsh -c` reads ~/.zshenv, and an option set there
# (sh_word_split, glob_subst, ksh_arrays…) must not change what a path check means.

# REPLY = the folder Xcode keeps DerivedData in (Xcode › Settings › Locations). Returns 1, the reason in REPLY, when
# there is no single folder. Xcode 27 reads IDECustomDerivedDataLocation from its defaults
# (+[IDEWorkspaceArena _standardDerivedDataLocationPathFragment]): missing or empty — the standard
# ~/Library/Developer/Xcode/DerivedData; an absolute path ("Custom") — that folder; a relative one ("Relative") —
# a folder of that name next to each project, so no one folder to show or clear.
derived_data() {
  emulate -L zsh
  local custom
  [[ $HOME == /?* ]] || { REPLY="DerivedData: HOME is not set"; return 1 }
  custom=$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null)
  case $custom in
    '')        REPLY=$HOME/Library/Developer/Xcode/DerivedData ;;
    '~'|'~/'*) REPLY=$HOME${custom#\~} ;;
    *'$('*)    REPLY="Xcode's DerivedData location uses a source tree (Settings › Locations): not supported"; return 1 ;;
    /*)        REPLY=$custom ;;
    *)         REPLY="Xcode keeps DerivedData next to each project (Settings › Locations › Relative)"; return 1 ;;
  esac
  return 0
}

# 0 when $1 — a resolved path — can only be Xcode's DerivedData: a real folder inside the user's home (never the
# home itself, never /), and, unless it is the standard place itself, holding nothing but what Xcode puts there: a
# folder per project (<name>-<28 letters>), *.noindex caches, SDK* module caches, .DS_Store, and what a clear moved
# aside. A custom location set to a folder of other things (~/Projects) is refused, not emptied — and so is the
# standard place when it is a symlink to one (DerivedData → ~/Documents). 1 with the reason in REPLY.
safe_to_clear() {
  emulate -L zsh
  local dd=$1 home std name tail
  [[ $HOME == /?* ]] || { REPLY="DerivedData: HOME is not set"; return 1 }
  home=${HOME:A}
  [[ $home == /?* ]] || { REPLY="DerivedData: the home folder is /"; return 1 }
  [[ $dd == /?* && $dd == "${dd:A}" ]] || { REPLY="DerivedData: \"$dd\" is not a full path"; return 1 }
  [[ $dd == "$home"/?* ]] || { REPLY="DerivedData is at $dd, outside your home folder: clear it in Xcode"; return 1 }
  [[ -d $dd && ! -L $dd ]] || { REPLY="DerivedData: $dd is not a folder"; return 1 }
  std=$home/Library/Developer/Xcode/DerivedData
  [[ $dd == "$std" ]] && return 0             # the standard place, no symlink on the way: all of it is Xcode's
  for name in "$dd"/*(DN:t); do
    tail=${name##*-}
    [[ $name == (*.noindex|SDK*|.DS_Store|.desmaptic-clearing-*) ]] && continue
    [[ $name == ?*-* && ${#tail} == 28 && $tail != *[^a-z]* ]] && continue
    REPLY="DerivedData at $dd holds \"$name\", which Xcode does not put there: not clearing it"
    return 1
  done
  return 0
}
