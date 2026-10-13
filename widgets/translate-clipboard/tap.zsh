#!/bin/zsh
# Translate tap: open the text on the Mac's clipboard in Google Translate, into the Mac's language
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

mode=tap

# ---- translate: identical in tap.zsh and hold.zsh ----
# The copied text never passes through the shell: osascript reads the clipboard, builds the address and
# opens it in the default browser itself, then answers with one word.
#   tap:  into the first of the Mac's preferred languages that Google Translate has (English if none).
#   hold: into English; on a Mac whose first language is English, into the next preferred language, if any.
# env -i: a browser osascript starts gets its environment; so a closed one gets the account's own, not the agent's token.
result=$(env -i /usr/bin/osascript -l JavaScript -e '
ObjC.import("AppKit");

function run(argv) {
  // Target codes as the Google Translate page lists them (tl=); a language it lacks is skipped.
  const known = new Set(`
    aa ab ace ach af ak alz am ar as av awa ay az ba bal ban bbc bci be bem ber ber-Latn bew bg bho bik bm
    bm-Nkoo bn bo br bs bts btx bua ca ce ceb cgg ch chk chm ckb cnh co crh crh-Latn crs cs cv cy da de din
    doi dov dv dyu dz ee el en eo es et eu fa fa-AF ff fi fj fo fon fr fr-CA fur fy ga gaa gd gl gn gom gu
    gv ha haw hi hil hmn hr hrx ht hu hy iba id ig ilo is it iu iu-Latn iw ja jam jw ka kac kek kg kha kk
    kl km kn ko kr kri ktu ku kv ky la lb lg li lij lmo ln lo lt ltg lua luo lus lv mad mai mak mam mfe mg
    mh mi min mk ml mn mni-Mtei mr ms ms-Arab mt mwr my ndc-ZW ne new nhe nl no nr nso nus ny oc om or os
    pa pa-Arab pag pam pap pl ps pt pt-PT qu rn ro rom ru rw sa sah sat sat-Latn scn sd se sg shn si sk sl
    sm sn so sq sr ss st su sus sv sw szl ta tcy te tet tg th ti tiv tk tl tn to tpi tr trp ts tt tum ty
    tyv udm ug uk ur uz ve vec vi war wo xh yi yo yua yue zap zh-CN zh-TW zu`.trim().split(/\s+/));
  // Where Google uses another code than macOS
  const alias = { he: "iw", jv: "jw", nb: "no", nn: "no", fil: "tl", kok: "gom", mni: "mni-Mtei", prs: "fa-AF" };

  // One entry of the preferred-language list ("ru-RU", "zh-Hans-CN", "pt-PT", "pa-Arab") as a Google
  // code, or "" when Google does not translate into that language.
  function google(tag) {
    const parts = String(tag).split(/[-_]/);
    const base = parts[0].toLowerCase();
    const lang = alias[base] || base;
    let script = "", region = "";
    for (const part of parts.slice(1)) {
      if (!script && /^[A-Za-z]{4}$/.test(part)) script = part[0].toUpperCase() + part.slice(1).toLowerCase();
      else if (!region && /^([A-Za-z]{2}|[0-9]{3})$/.test(part)) region = part.toUpperCase();
    }
    if (lang === "zh") return script === "Hant" || (!script && /^(TW|HK|MO)$/.test(region)) ? "zh-TW" : "zh-CN";
    if (lang === "pt") return region && region !== "BR" ? "pt-PT" : "pt";
    for (const code of [lang + "-" + script, lang + "-" + region, lang]) {
      if (known.has(code)) return code;
    }
    return "";
  }

  const codes = (ObjC.deepUnwrap($.NSLocale.preferredLanguages) || []).map(google).filter((code) => code);
  const first = codes[0] || "en";
  let target = first;
  if (argv[0] === "hold") target = first !== "en" ? "en" : (codes.find((code) => code !== "en") || "en");

  // What a password manager (or the New Password button) copies is marked so; it never goes to a website.
  const board = $.NSPasteboard.generalPasteboard;
  // The last three are the older spellings of the same marks, which macOS still knows (1Password before 8 uses one).
  const marks = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
    "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping"];
  const items = ObjC.unwrap(board.pasteboardItems) || [];
  const typeLists = [ObjC.deepUnwrap(board.types) || []].concat(items.map((item) => ObjC.deepUnwrap(item.types) || []));
  if (typeLists.some((types) => types.some((type) => marks.includes(type)))) return "concealed";

  const copied = board.stringForType("public.utf8-plain-text");
  if (copied.isNil()) return items.length ? "notext" : "empty";
  const text = copied.js.replace(/\r\n?/g, "\n").trim();
  if (!text) return "blank";

  // Google takes 5000 characters at a time, and its server refuses an address longer than about 16 KB
  // (16,347 characters of text passed, 16,367 did not), so the text stops at whichever comes first,
  // always on a whole character: a pair of UTF-16 halves (an emoji) is never split.
  const head = "https://translate.google.com/?sl=auto&tl=" + target + "&text=";
  const tail = "&op=translate";
  let units = 0, size = head.length + tail.length, encoded = "";
  for (const character of text) {
    let piece;
    try { piece = encodeURIComponent(character); } catch (error) { piece = "%EF%BF%BD"; }   // a stray half
    if (units + character.length > 5000 || size + piece.length > 16000) break;
    units += character.length;
    size += piece.length;
    encoded += piece;
  }
  const link = $.NSURL.URLWithString(head + encoded + tail);
  if (link.isNil()) return "badlink";
  return $.NSWorkspace.sharedWorkspace.openURL(link) ? "ok" : "unopened";
}' $mode)

case $result in
  ok)        exit 0 ;;
  empty)     print -u2 -- "translate: the clipboard is empty" ;;
  notext)    print -u2 -- "translate: there is no text on the clipboard" ;;
  blank)     print -u2 -- "translate: the clipboard holds only spaces" ;;
  concealed) print -u2 -- "translate: the clipboard holds a password; it is not sent to a website" ;;
  badlink)   print -u2 -- "translate: could not build the Google Translate address" ;;
  unopened)  print -u2 -- "translate: macOS did not open the page in the browser" ;;
  *)         print -u2 -- "translate: osascript failed${result:+ ($result)}" ;;
esac
exit 1
