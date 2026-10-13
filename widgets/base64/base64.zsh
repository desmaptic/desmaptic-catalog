# Base64: the text on the Mac's clipboard to Base64 (tap), or Base64 on the clipboard back to text (hold).
# Both commands are one line that names the mode, then this file (item.json):
#   "mode=encode\n@file:base64.zsh"   — tap
#   "mode=decode\n@file:base64.zsh"   — hold
# The copied text never passes through the shell: osascript reads the clipboard through NSPasteboard,
# converts it, writes the result back as plain text and answers with one word. (pbpaste and pbcopy would
# mangle every non-ASCII character here: they follow LC_ALL, which is C.) A refusal changes nothing.
[[ $mode == (encode|decode) ]] || { print -u2 -- "base64: unknown mode \"$mode\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

result=$(osascript -l JavaScript - $mode <<'JXA'
ObjC.import("AppKit");

function run(argv) {
  // Base64 of up to a million characters, that is text of up to 750,000 bytes of UTF-8: far more than anyone
  // converts by hand, and the whole job stays well under a second (the text is converted by Foundation, never
  // copied into JavaScript). Both ways keep to the same bound, so whatever one gives, the other takes back.
  const encode = argv[0] === "encode";
  const limit = 1000000, textLimit = limit / 4 * 3;
  // JXA hands NSInteger and NSUInteger over as strings ("0" === 0 is false, "12" + 4 is "124"): every
  // length, count and range is read through Number.
  const board = $.NSPasteboard.generalPasteboard;
  const change = Number(board.changeCount);

  // What a password manager (or the New Password button) copies is marked so; the same marks as
  // Translate's. Encoded, it would stay readable in every clipboard history.
  const marks = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
    "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping"];
  const items = ObjC.unwrap(board.pasteboardItems) || [];
  const typeLists = [ObjC.deepUnwrap(board.types) || []].concat(items.map((item) => ObjC.deepUnwrap(item.types) || []));
  const holds = (wanted) => typeLists.some((types) => types.some((type) => wanted.includes(type)));
  if (holds(marks)) return "concealed";
  // Files copied in Finder come with their names as text: encoding the name would replace the files
  // on the clipboard with something nobody asked for.
  if (holds(["public.file-url"])) return "files";

  const copied = board.stringForType("public.utf8-plain-text");
  if (copied.isNil()) return items.length ? "notext" : "empty";
  // A quick bound before any work: UTF-8 never takes fewer bytes than the text has UTF-16 units, and wrapped
  // Base64 of a million characters has far fewer than two million with its line breaks and indents.
  if (Number(copied.length) > (encode ? textLimit : 2 * limit)) return encode ? "toolarge" : "toolong";
  const spaces = $.NSCharacterSet.whitespaceAndNewlineCharacterSet;
  if (Number(copied.stringByTrimmingCharactersInSet(spaces).length) === 0) return "blank";

  let result;
  if (encode) {
    // The text exactly as copied, line breaks included, as UTF-8; one line of standard Base64 with = padding.
    const data = copied.dataUsingEncoding($.NSUTF8StringEncoding);
    if (data.isNil()) return "unencodable";
    if (Number(data.length) > textLimit) return "toolarge";
    result = data.base64EncodedStringWithOptions(0);
  } else {
    // Spaces and line breaks are skipped wherever they are (Base64 wrapped at 64 or 76 characters, pasted
    // with an indent); the URL-safe alphabet (- and _) reads as the standard one (+ and /); missing =
    // padding is added back, and padding that is there must be right.
    let code = copied.componentsSeparatedByCharactersInSet(spaces).componentsJoinedByString("");
    code = code.stringByReplacingOccurrencesOfStringWithString("-", "+")
      .stringByReplacingOccurrencesOfStringWithString("_", "/");
    const length = Number(code.length);
    if (length > limit) return "toolong";
    let pads = 0;
    while (pads < 3 && pads < length && code.characterAtIndex(length - 1 - pads) === 61) pads++;   // "="
    const body = code.substringToIndex(length - pads);
    const size = length - pads;
    const alphabet = $.NSCharacterSet.characterSetWithCharactersInString(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
    if (size === 0 || Number(body.rangeOfCharacterFromSet(alphabet.invertedSet).length) !== 0) return "invalid";
    const rest = size % 4;
    if (rest === 1 || pads > 2 || (pads > 0 && (rest + pads) % 4 !== 0)) return "invalid";
    const padded = rest ? body.stringByPaddingToLengthWithStringStartingAtIndex(size + 4 - rest, "=", 0) : body;
    const data = $.NSData.alloc.initWithBase64EncodedStringOptions(padded, 0);
    if (data.isNil()) return "invalid";
    // Text is valid UTF-8 without control characters other than tab and line breaks: an image, an archive
    // or a key decodes to bytes that are not, and pasted as text they would be garbage.
    const text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (text.isNil()) return "binary";
    const controls = $.NSMutableCharacterSet.alloc.init;
    controls.addCharactersInRange($.NSMakeRange(0x00, 0x09));   // U+0000…U+0008
    controls.addCharactersInRange($.NSMakeRange(0x0E, 0x12));   // U+000E…U+001F
    controls.addCharactersInRange($.NSMakeRange(0x7F, 0x21));   // U+007F…U+009F
    if (Number(text.rangeOfCharacterFromSet(controls).length) !== 0) return "binary";
    result = text;
  }

  // Something new was copied while this ran: it stays, the result goes nowhere.
  if (Number(board.changeCount) !== change) return "changed";
  board.clearContents;
  return board.setStringForType(result, "public.utf8-plain-text") ? "ok" : "unwritable";
}
JXA
)

case $result in
  ok)          exit 0 ;;
  empty)       print -u2 -- "base64: the clipboard is empty" ;;
  notext)      print -u2 -- "base64: there is no text on the clipboard" ;;
  files)       print -u2 -- "base64: the clipboard holds files, not text" ;;
  blank)       print -u2 -- "base64: the clipboard holds only spaces" ;;
  concealed)   print -u2 -- "base64: the clipboard holds a password; it is left as it is" ;;
  toolarge)    print -u2 -- "base64: the text on the clipboard is over 750,000 bytes; its Base64 would pass 1,000,000 characters" ;;
  toolong)     print -u2 -- "base64: the clipboard holds more than 1,000,000 characters of Base64" ;;
  unencodable) print -u2 -- "base64: the text on the clipboard is not valid Unicode" ;;
  invalid)     print -u2 -- "base64: the clipboard does not hold Base64" ;;
  binary)      print -u2 -- "base64: the clipboard does not decode to text (an image, an archive, or not Base64 at all)" ;;
  changed)     print -u2 -- "base64: something new was copied meanwhile; it is left as it is" ;;
  unwritable)  print -u2 -- "base64: the clipboard refused the result" ;;
  *)           print -u2 -- "base64: osascript failed${result:+ ($result)}" ;;
esac
exit 1
