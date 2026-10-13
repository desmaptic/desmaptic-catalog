# UUID, the tap and the long press: a new UUID on the Mac's clipboard, in lowercase. Each command is one line that
# names the version, then this file (item.json):
#   "version=4\n@file:copy.zsh"   — random (RFC 9562 version 4);
#   "version=7\n@file:copy.zsh"   — time-ordered (RFC 9562 version 7): one made in a later millisecond sorts after.
# A UUID is no secret, so unlike New Password it is not marked concealed: clipboard managers may keep it.
emulate -R zsh                                  # zsh's own options: the substrings below count from 1
[[ $version == (4|7) ]] || { print -u2 -- "uuid: unknown version \"$version\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# uuid4: macOS's uuidgen makes a random version 4 UUID; it prints it in capitals.
uuid4() { uuidgen | tr A-Z a-z }

# uuid7: RFC 9562 version 7, as hex digits —
#   tttttttt-tttt  the Unix time in milliseconds, 48 bits, most significant first
#   7rrr           the version, then 12 random bits
#   Vrrr           the variant (binary 10, so V is 8, 9, a or b) with 2 random bits, then 12 more
#   rrrrrrrrrrrr   48 random bits — 62 random bits after the variant in all
uuid7() {
  zmodload zsh/datetime 2>/dev/null || return 1
  local -i ms
  (( ms = EPOCHREALTIME * 1000 ))               # arithmetic reads the seconds as a number: no decimal comma
  (( ms > 0 && ms < 16**12 )) || return 1
  local time random variant
  printf -v time '%012x' $ms
  random=$(od -An -v -N10 -tx1 /dev/urandom) || return 1
  random=${random//[^0-9a-f]/}                  # 10 bytes: 20 hex digits, 19 of them used
  (( ${#random} == 20 )) || return 1
  printf -v variant '%x' $(( (16#${random[4]} & 3) | 8 ))
  print -rn -- "${time[1,8]}-${time[9,12]}-7${random[1,3]}-${variant}${random[5,7]}-${random[8,19]}"
}

if [[ $version == 4 ]]; then
  id=$(uuid4)
else
  id=$(uuid7)
fi
[[ $id =~ "^[0-9a-f]{8}-[0-9a-f]{4}-${version}[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$" ]] ||
  { print -u2 -- "uuid: could not make a version $version UUID"; exit 1 }

# Pure ASCII, so pbcopy's encoding (it follows the locale) does not matter; no line break after it.
print -rn -- "$id" | pbcopy || { print -u2 -- "uuid: the clipboard refused the UUID"; exit 1 }
exit 0
