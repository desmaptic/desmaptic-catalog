#!/bin/zsh
# Say Aloud tap: the Mac speaks the text typed on the phone ($DESMAPTIC_INPUT) with macOS's own `say`, out of its
# speakers or whatever it plays sound through. The voice is the Mac's system voice when it speaks the text's language;
# otherwise the first installed voice of that language, one of Apple's own voices before the novelty ones (Bells, Boing).
# The language is guessed from the text (NaturalLanguage), with the Mac's preferred languages weighing more. The text
# reaches `say` through a pipe, never as an argument, and the program that picks the voice reads it from its environment.
# The tap waits for the speech, the speaker on the button meanwhile: a tap lasts at most 60 s, so a long text is cut off
# there (the agent stops the tap, and the tap its `say`), and the button takes no other tap until then.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
speaker=""
trap '[[ -n $speaker ]] && kill $speaker 2>/dev/null; exit 0' TERM INT

# call <endpoint> <json>: posts to the agent and prints its HTTP code. The token goes in through a descriptor,
# not the command line, where any user of the Mac could read it.
call() {
  curl -q -s -o /dev/null -m 5 -w '%{http_code}' "$api/$1" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$2"
}

# fail <kind> <message>: the toast after the tap says why (/api/error), then the tap ends.
fail() {
  call error "$(jq -nc --arg c "$cell" --arg k "$1" --arg m "$2" '{cellId: $c, kind: $k, message: $m}')" >/dev/null
  print -ru2 -- "Say Aloud: $2"
  exit 1
}

[[ -n ${DESMAPTIC_INPUT//[[:space:]]/} ]] || fail other "Nothing to say: the text is empty"

# ---- the voice: a name for say -v, or nothing for the system voice ----
read -r -d '' js <<'JS'
ObjC.import("AppKit");
ObjC.import("NaturalLanguage");

function run() {
  try {
    const value = $.NSProcessInfo.processInfo.environment.objectForKey("DESMAPTIC_INPUT");
    const text = value.isNil() ? "" : value.js;
    const base = (code) => String(code || "").split(/[-_]/)[0].toLowerCase();
    const preferred = (ObjC.deepUnwrap($.NSLocale.preferredLanguages) || []).map(String);

    // A short text ("Привет") alone may read as a neighbour language: the catalog's languages and, more, the Mac's own
    // tip the balance.
    const hints = {};
    for (const code of ["en", "de", "es", "fr", "ru"]) hints[code] = 0.1;
    for (const code of preferred) hints[base(code)] = 0.3;
    const recognizer = $.NLLanguageRecognizer.alloc.init;
    recognizer.languageHints = $(hints);
    recognizer.processString(text);
    const language = base(ObjC.unwrap(recognizer.dominantLanguage));
    if (!language || language === "und") return "";

    const attribute = (voice, key) => {
      const v = $.NSSpeechSynthesizer.attributesForVoice(voice).objectForKey(key);
      return v.isNil() ? "" : String(ObjC.unwrap(v));
    };
    if (base(attribute($.NSSpeechSynthesizer.defaultVoice, "VoiceLocaleIdentifier")) === language) return "";

    // Apple's own voices first (premium, enhanced, compact), the novelty ones last; then the Mac's preferred region.
    const rank = (id) => /^com\.apple\.voice\.premium\./.test(id) ? 0 : /^com\.apple\.voice\.enhanced\./.test(id) ? 1
      : /^com\.apple\.voice\.compact\./.test(id) ? 2 : /^com\.apple\.speech\.synthesis\.voice\./.test(id) ? 4 : 3;
    const regions = preferred.map((code) => code.replace("-", "_"));
    let best = null;
    for (const voice of ObjC.unwrap($.NSSpeechSynthesizer.availableVoices) || []) {
      const locale = attribute(voice, "VoiceLocaleIdentifier");
      if (base(locale) !== language) continue;
      const score = rank(String(ObjC.unwrap(voice))) * 2 + (regions.some((r) => locale.startsWith(r)) ? 0 : 1);
      if (best === null || score < best.score) best = { score: score, name: attribute(voice, "VoiceName") };
    }
    return best === null ? "" : best.name;
  } catch (e) {
    return "";
  }
}
JS
voice=$(osascript -l JavaScript -e "$js" 2>/dev/null)
voice=${voice%%$'\n'*}

# ---- the speech, with the speaker on the button while it lasts ----
print -rn -- "$DESMAPTIC_INPUT" | say ${voice:+-v} ${voice:+"$voice"} -f - 2>/dev/null &
speaker=$!
call update-button "{\"cellId\":\"$cell\",\"icon\":\"speaker.wave.3.fill\"}" >/dev/null
wait $speaker
spoke=$?
speaker=""
call update-button "{\"cellId\":\"$cell\",\"reset\":true}" >/dev/null
# 143: say was stopped (TERM) from outside the tap, which is no failure of the tap.
(( spoke == 0 || spoke == 143 )) || fail other "macOS did not speak the text (say ended with $spoke)"
exit 0
