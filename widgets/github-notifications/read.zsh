# GitHub notifications › long press: marks every notification read (`gh api -X PUT notifications`), confirmed by a
# second long press within 10 seconds. After gh.zsh (item.json): "@file:gh.zsh\n@file:read.zsh".
#
# The first long press only arms it: gallery/{{CELL_ID}}/armed holds its time, and the loop turns the bell green with a
# ring that runs out in 10 s. A second one in that time marks read what came until the first one (last_read_at), so a
# notification that arrives in between stays unread; later, it arms again. While it runs gallery/{{CELL_ID}}/marking
# holds its time, and once GitHub took it gallery/{{CELL_ID}}/marked does: the loop then shows "0". A grey bell's long
# press says what it means instead.

# fail <kind> <message>: the reason as the press's answer (the toast), then exit 1.
fail() {
  [[ -n $own ]] && zf_rm -f "$own/marking" 2>/dev/null
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "GitHub notifications: $2"
  exit 1
}

[[ -n $own ]] || fail permission "The button has nowhere to save its state on the Mac."
gh_found || fail ${REPLY%% *} "${REPLY#* }"
said=""
[[ -f $own/problem ]] && IFS= read -r said < "$own/problem" 2>/dev/null
[[ -n $said ]] && fail ${said%% *} "${said#* }"

stamp armed; armed=$REPLY
if (( armed == 0 || EPOCHREALTIME - armed > confirm )); then
  zf_mkdir -p "$own" 2>/dev/null
  print -r -- $EPOCHREALTIME > "$own/armed" 2>/dev/null || fail permission "The button can’t save its state on the Mac."
  exit 0
fi
zf_rm -f "$own/armed" 2>/dev/null
print -r -- $EPOCHREALTIME > "$own/marking" 2>/dev/null

since=$(date -u -r ${armed%.*} '+%Y-%m-%dT%H:%M:%SZ')
gh_api 30 -X PUT notifications -f last_read_at=$since -F read=true --silent
rc=$?
if (( rc != 0 )); then
  gh_refusal $rc "GitHub didn’t mark the notifications as read"
  REPLY=${REPLY#* }
  fail ${REPLY%% *} "${REPLY#* }"
fi
print -r -- $EPOCHREALTIME > "$own/marked" 2>/dev/null
zf_rm -f "$own/marking" 2>/dev/null
exit 0
