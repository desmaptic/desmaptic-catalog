# Microsoft Teams › the meeting controls: Mic, Camera, Raise Hand, Share (and Stop), Meeting (and Leave). Functions
# only — every script of these buttons starts with this file (app.json): the live loop of Mic and Camera (live.zsh)
# and every tap and long press (press.zsh).
#
# The new Teams (com.microsoft.teams2) is a native window around Microsoft's web client: its meeting controls are web
# buttons, not menu items, and it has no AppleScript dictionary. They are read and pressed through the Accessibility
# API from JavaScript for Automation — no Apple event, so never the Automation question, and a press lands in the
# meeting window without bringing Teams forward. Each control is found by its DOM id, the same in every language of
# Teams (Accessibility shows it as AXDOMIdentifier): microphone-button, video-button, raisehands-button, share-button,
# chat-button, roster-button, hangup-button (web client of Teams 26043.2109.4484.3337, 2026-09-27; checked read-only
# on this Mac in a meeting). Whether the mic or the camera is on is only in the control's label, which names what a
# click does ("Mute mic" while the mic is on): the reader knows the labels of all 63 languages of the web client, from
# its own translations (calling_mute_aria_label, calling_unmute_aria_label, calling_stopVideo_aria_label,
# calling_startVideo_aria_label).
#
# What one read walks: Teams' windows (AXWindows, one call), then each window depth first — one call per element
# (AXUIElementCopyMultipleAttributeValues: role, children, DOM id), skipping text, images, lists and tables — until
# both controls are found, then one call per control for its label and whether it is enabled. Measured read-only on
# this Mac: the meeting window is about 65 elements, the toolbar 17 levels down, both controls found after 45; the
# main window is about 120 more. The long-lived reader keeps the two controls it found and, while they are still
# there, reads only their labels. Window titles and everything a window shows are never read.
# A press through Accessibility also moves Teams' keyboard focus to the control (seen with Mic), and Space in Teams
# would then press it again: a press that leaves Teams behind finds what had the focus in that window before (AXFocused
# reads true in the background too) and gives it back — or, when that was inside a list or not found, to the page.

# REPLY = the process id of this account's Teams; 1 when it is not running. lsappinfo asks Launch Services by bundle id:
# no permission, and nothing Teams notices.
teams_pid() {
  emulate -L zsh
  local out
  out=$(lsappinfo info -only pid -app com.microsoft.teams2 2>/dev/null)
  REPLY=${${out#*\"pid\"=}%%[^0-9]*}
  [[ $out == *'"pid"='[0-9]* && $REPLY == <1-> ]]
}

# Keeps a state line in the file the Teams buttons share, when it is newer than the one there. A line is
# "<ms the read began> <teams> <mic> <camera>" (the reader's words, below); a read that began earlier never replaces
# a later one — a tap writes what it saw after its press, and a read already running must not undo that.
teams_keep() {   # $1 shared folder, $2 the line
  emulate -L zsh
  local asked=${2%% *} old=""
  [[ -n $1 && $asked == <-> ]] || return 1
  zf_mkdir -p $1 2>/dev/null
  [[ -r $1/state ]] && read -r old < $1/state 2>/dev/null
  old=${old%% *}
  [[ $old == <-> ]] && (( old >= asked )) && return 0
  print -r -- "$2" > $1/state.$$ 2>/dev/null && zf_mv -f $1/state.$$ $1/state 2>/dev/null
}

# REPLY = the reader, a JavaScript for Automation program (osascript -l JavaScript -e "$REPLY" <mode> …):
#   read <pid>                            prints one line: <ms> <teams> <mic> <camera> <elements visited>
#   loop <pid> <period> <idle> <seconds>  a line per read: every <period> s while a meeting is on, every <idle> s
#                                         while there is none; ends after <seconds> (the bridge keeps every object it
#                                         hands to JavaScript, so a long-lived reader grows) or without Accessibility.
#                                         When Teams quits it says busy: the script, which asks lsappinfo, stops it
#   press <pid> <id|-> <show|-> [labels]  presses the control with that DOM id; "show" first brings the meeting
#                                         window to the front (id "-": only that); with a label set (shareIdle,
#                                         shareStop, leave) it presses only while the control's label is one of those.
#                                         Prints nothing or !<why not> on the first line; after Mic or Camera, the
#                                         state line once the label has changed
# <teams>: meeting, none (no meeting), wait (its web content is not exposed yet), busy (Teams did not answer),
# noax (Desmaptic Agent has no Accessibility), off (not running). <mic>: on, off, locked (greyed out), unknown (a label
# this reader does not know), - (no such control, or not in a meeting). <camera>: on, off, none (greyed out: no camera,
# or not allowed), unknown, - .
teams_program() {
  read -r -d '' REPLY <<'JS'
ObjC.import("AppKit");
ObjC.import("ApplicationServices");

const MIC = "microphone-button", CAMERA = "video-button";
// The controls' labels in every language of the Teams web client. A label names what a click does: "Mute mic" while
// the mic is on, "Stop sharing" while you share. The hang-up button is pressed only while it says "Leave"
// (calling_ubar_hangup_button_tooltip): in a breakout room it says "Leave room" and takes you back to the main
// meeting, when monitoring a call "End monitoring", in follow mode "Unfollow". The label does not tell "Leave" from
// "End meeting" for everyone: this client never makes that the main click (the primary action is Leave, End
// monitoring, Unfollow or Return — its code, 26043.2109.4484.3337), but it would still label it "Leave" if a later
// one did; ending for everyone stays behind Teams' own menu next to the button.
const LABELS = {
  micOn: [
    "Ativar mudo do\u00a0microfone", "Bisukan mikrofon", "Couper le micro", "Demp mikrofon", "Demp mikrofonen",
    "Demp mikrofoon", "Desactivar audio del micrófono", "Desaktibatu mikrofonoa", "Desativar som do microfone",
    "Dezactivați sunetul microfonului", "Disattiva microfono", "I-mute ang mikropono",
    "Iddiżattiva l-ħoss tal-mikrofonu", "Inaktivera mikrofon", "Isključi mikrofon", "Isključite zvuk mikrofona",
    "Izklopi mikrofon", "Izslēgt mikrofonu", "Matikan suara mikrofon", "Mbyll mikrofonin", "Microfoon dempen",
    "Mikrofon elnémítása", "Mikrofon ovozini oʻchirish", "Mikrofon stummschalten", "Mikrofonu sessize al",
    "Mikrofonu səssiz et", "Mute mic", "Mykistä mikrofoni", "Nutildyti mikrofoną",
    "Privremeno isključi zvuk mikrofona", "Silencia el micròfon", "Silenciar micrófono", "Slå mikrofonen fra",
    "Slökkva á hljóðnema", "Stlmiť mikrofón", "Tewi'r meic", "Tắt tiếng micrô", "Vaigista mikrofon", "Wycisz mikrofon",
    "Ztlumit mikrofon", "Σίγαση μικροφώνου", "Вимкнути мікрофон", "Изключване на звука на микрофона",
    "Исклучи звук на микрофон", "Микрофон дыбысын өшіру", "Отключить микрофон", "Привремено искључи микрофон",
    "השתק את המיקרופון", "قطع صدای میکروفون", "كتم الميكروفون", "माइक म्यूट करें", "ปิดเสียงไมโครโฟน", "ປິດສຽງໄມ",
    "მიკროფონის დადუმება", "បិទសំឡេងមីក្រូហ្វូន", "マイクのミュート", "将麦克风静音", "將麥克風靜音", "마이크 음소거"
  ],
  micOff: [
    "Activa el so del micròfon", "Activar son do micrófono", "Activați sunetul microfonului", "Aktibatu mikrofonoa",
    "Ativar som do microfone", "Attiva l-ħoss tal-mikrofonu", "Atšaukti mikrofono nutildymą", "Bật tiếng micrô",
    "Dad-ddistewi’r meic", "Desativar mudo\u00a0do microfone", "Hap mikrofonin", "I-unmute ang mikropono",
    "Ieslēgt mikrofonu", "Kveikja á hljóðnema", "Microfoon niet meer dempen", "Mikrofon ovozini yoqish",
    "Mikrofon visszahangosítása", "Mikrofon wieder aktivieren", "Mikrofonun sesini aç", "Mikrofonun səsini aç",
    "Nyahbisu mikrofon", "Nyalakan suara mikrofon", "Ontdemp mikrofoon", "Opphev demping av mikrofon",
    "Opphev demping av mikrofonen", "Poista mikrofonin mykistys", "Ponovo uključi zvuk mikrofona",
    "Reactivar audio del micrófono", "Riattiva microfono", "Réactiver le micro", "Slå mikrofonen til",
    "Slå på mikrofon", "Tühista mikrofoni vaigistus", "Uključi mikrofon", "Uključite mikrofon", "Unmute mic",
    "Vklopi mikrofon", "Wyłącz wyciszenie mikrofonu", "Zrušit ztlumení mikrofonu", "Zrušiť stlmenie mikrofónu",
    "Κατάργηση σίγασης μικροφώνου", "Вклучи звук на микрофон", "Включване на звука на микрофон", "Включить микрофон",
    "Микрофон дыбысын қосу", "Поново укључи звук микрофона", "Увімкнути мікрофон", "בטל את השתקת המיקרופון",
    "إلغاء كتم الميكروفون", "وصل مجدد صدای میکروفون", "माइक अनम्यूट करें", "เปิดเสียงไมโครโฟน", "ເປີດສຽງໄມ",
    "მიკროფონის ხმის ჩართვა", "បើក\u200bសំឡេងមីក្រូហ្វូន", "マイクのミュートを解除", "取消麥克風靜音", "取消麦克风静音", "마이크 음소거 해제"
  ],
  cameraOn: [
    "Apagar la cámara", "Camera uitschakelen", "Desactiva la càmera", "Desactivar cámara", "Desaktibatu kamera",
    "Desativar câmara", "Desativar câmera", "Dezactivați camera", "Diffodd y camera", "Disattiva videocamera",
    "Désactiver la caméra", "I-off ang camera", "Isključite kameru", "Isključivanje kamere", "Itfi l-kamera",
    "Izklopi kamero", "Izslēgt kameru", "Išjungti kamerą", "Kamera ausschalten", "Kamera kikapcsolása",
    "Kamerani oʻchirish", "Kameranı qeyri-aktiv et", "Kamerayı kapat", "Lülita kaamera välja", "Matikan kamera",
    "Sammuta kamera", "Skakel kamera af", "Slå av kameraet", "Slå kameraet fra", "Slökkva á myndavél",
    "Stäng av kameran", "Turn camera off", "Tắt camera", "Vypnout kameru", "Vypnúť kameru", "Wyłącz kamerę",
    "Çaktivizo kamerën", "Απενεργοποίηση κάμερας", "Вимкнути камеру", "Изключване на камерата", "Исклучи камера",
    "Искључи камеру", "Камераны өшіру", "Отключить камеру", "כבה מצלמה", "إيقاف تشغيل الكاميرا", "خاموش کردن دوربین",
    "कैमरा बंद करें", "ปิดกล้อง", "ປິດກ້ອງຖ່າຍຮູບ", "კამერის გამორთვა", "បិទកាមេរ៉ា", "カメラをオフにする", "关闭摄像头", "關閉相機",
    "카메라 끄기"
  ],
  cameraOff: [
    "Activa la càmera", "Activar cámara", "Activați camera", "Activer la caméra", "Aktibatu kamera",
    "Aktivera kameran", "Aktivizo kamerën", "Ativar câmara", "Ativar câmera", "Attiva videocamera", "Bật camera",
    "Camera inschakelen", "Encender la cámara", "Hidupkan kamera", "I-on ang camera", "Ieslēgt kameru",
    "Ixgħel il-kamera", "Kamera aktivieren", "Kamera bekapcsolása", "Kamerani yoqish", "Kameranı aktivləşdir",
    "Kamerayı aç", "Kveikja á myndavél", "Käynnistä kamera", "Lülita kaamera sisse", "Rhoi'r camera ar waith",
    "Skakel kamera aan", "Slå kamera til", "Slå på kameraet", "Turn camera on", "Uključi kameru", "Uključite kameru",
    "Uključivanje kamere", "Vklopi kamero", "Włącz kamerę", "Zapnout kameru", "Zapnúť kameru", "Įjungti kamerą",
    "Ενεργοποίηση κάμερας", "Вклучи камера", "Включване на камерата", "Включить камеру", "Камераны қосу",
    "Увімкнути камеру", "Укључи камеру", "הפעל מצלמה", "تشغيل الكاميرا", "روشن کردن دوربین", "कैमरा चालू करें",
    "เปิดกล้อง", "ເປີດກ້ອງຖ່າຍຮູບ", "კამერის ჩართვა", "បើកកាមេរ៉ា", "カメラをオン", "打开摄像头", "開啟相機", "카메라 켜기"
  ],
  shareIdle: [
    "Bendrinti", "Berbagi", "Chia sẻ", "Comparte", "Comparteix", "Compartilhar", "Compartir", "Condividi", "Deel",
    "Deila", "Del", "Dela", "Dele", "Delen", "Deli", "Ibahagi", "Ixxerja", "Jaa", "Jaga", "Kongsi", "Kopīgot",
    "Megosztás", "Ndaj", "Partager", "Partajați", "Partekatu", "Partilhar", "Paylaş", "Podijeli", "Rhannu", "Sdílet",
    "Share", "Skupna raba", "Teilen", "Udostępnij", "Ulashish", "Zdieľať", "Κοινή χρήση", "Бөлісу", "Поделите",
    "Поделиться", "Поділитися", "Сподели", "Споделяне", "שיתוף", "اشتراک\u200cگذاری", "مشاركة", "साझा करें", "แชร์",
    "ແຊຣ໌", "გაზიარება", "ចែករំលែក", "共享", "共有", "分享", "공유"
  ],
  shareStop: [
    "Arrêter le partage", "Berhenti berkongsi", "Deixa de compartir", "Deixar de compartir", "Dejar de compartir",
    "Delen stoppen", "Dừng chia sẻ", "Hentikan berbagi", "Hou op deel", "Hætta að deila", "Ieqaf ixxerja",
    "Ihinto ang pagbabahagi", "Interrompi condivisione", "Lopeta jakaminen", "Lõpeta jagamine", "Megosztás leállítása",
    "Ndalo bashkëndarjen", "Obustavi deljenje", "Opriți distribuirea", "Opriți partajarea", "Parar de compartilhar",
    "Parar de compartir", "Parar de partilhar", "Paylaşmanı dayandır", "Paylaşımı durdur", "Prestani dijeliti",
    "Prestanite dijeliti", "Pārtraukt koplietošanu", "Přestat sdílet", "Sluta dela", "Stabdyti bendrinimą",
    "Stop deling", "Stop sharing", "Stopio rhannu", "Stopp deling", "Teilen beenden", "Ulashuvni to‘xtatish",
    "Ustavi skupno rabo", "Utzi partekatzeari", "Zastaviť zdieľanie", "Zatrzymaj udostępnianie", "Zaustavi deljenje",
    "Zaustavi dijeljenje", "Zaustavi zajedničko korištenje", "Διακοπή κοινοποίησης", "Бөлісуді тоқтату",
    "Відкликати доступ", "Відкликати спільний доступ", "Заустави дељење", "Ортақ пайдалануды тоқтату",
    "Отменить общий доступ", "Престани со споделување", "Спиране на споделянето", "Спри споделянето", "הפסק את השיתוף",
    "إيقاف المشاركة", "توقف اشتراک\u200cگذاری", "साझाकरण रोकें", "หยุดการแชร์", "ຢຸດການແຊຣ໌", "ຢຸດການແບ່ງປັນ",
    "გაზიარების შეწყვეტა", "ឈប់ចែករំលែក", "停止共享", "停止分享", "共有を停止", "共有停止", "공유 중지"
  ],
  leave: [
    "Abbandona", "Avslutt", "Ayrıl", "Dil", "Forlad", "Forlat", "Gadael", "Hætta", "Ieșiți", "Irten", "Itlaq", "Ix",
    "Iziet", "Išeiti", "Keluar", "Kilépés", "Lahku", "Leave", "Lämna", "Napusti", "Odejít", "Odísť", "Poistu",
    "Quitter", "Rời đi", "Sair", "Salir", "Saír", "Sluiten", "Surt", "Tark etish", "Tinggalkan", "Umalis", "Verlaat",
    "Verlassen", "Wyjdź", "Zapusti", "Çıx", "Αποχώρηση", "Вийти", "Выйти", "Напускане", "Напусти", "Напушти", "Шығу",
    "צא", "ترک", "مغادرة", "छोड़ दें", "ออก", "ອອກ", "გასვლა", "ចាកចេញ", "退出", "退出します", "離開", "나가기"
  ]
};
// Compared with the spaces evened out: some translations have a no-break space where the page may give a plain one.
function norm(s) { return s.replace(/[\u00a0\u202f]/g, " ").replace(/\s+/g, " ").trim(); }
for (const k in LABELS) LABELS[k] = LABELS[k].map(norm);
// Nothing of the meeting toolbar lives under these: not walked.
const SKIP = { AXStaticText: 1, AXImage: 1, AXTable: 1, AXList: 1, AXOutline: 1, AXTextArea: 1, AXTextField: 1,
  AXComboBox: 1, AXHeading: 1, AXLink: 1, AXRow: 1, AXCell: 1, AXScrollBar: 1, AXMenu: 1, AXMenuBar: 1 };
const WALK = $(["AXRole", "AXChildren", "AXDOMIdentifier"]);
const LOOK = $(["AXDOMIdentifier", "AXDescription", "AXEnabled"]);
const FOCUS = $(["AXRole", "AXChildren", "AXFocused"]);
const NO_AX = -25211, CANNOT = -25204;

const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
function put(text) {
  const data = $(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
  if (!data.isNil()) stdout.writeData(data);
}
function str(o) { try { return o.isKindOfClass($.NSString) ? o.js : ""; } catch (e) { return ""; } }
function yes(o) { try { return o.isKindOfClass($.NSNumber) && o.boolValue; } catch (e) { return false; } }

let visited = 0;
function copy(el, names) {                  // → NSArray of the values, or the Accessibility error code
  const v = Ref();
  const e = $.AXUIElementCopyMultipleAttributeValues(el, names, 0, v);
  return e === 0 ? ObjC.castRefToObject(v[0]) : e;
}
function value(el, name) {
  const v = Ref();
  const e = $.AXUIElementCopyAttributeValue(el, $(name), v);
  return e === 0 ? ObjC.castRefToObject(v[0]) : e;
}
function setFlag(el, name) { return $.AXUIElementSetAttributeValue(el, $(name), $.NSNumber.numberWithBool(true)); }
// Teams exposes its web content only to a client that asks for it, and the first read after asking may find nothing.
// A hung Teams answers every call after the timeout: 2 s for every element this process asks, not only the app's.
function appElement(pid) {
  const app = $.AXUIElementCreateApplication(pid);
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 2);
  $.AXUIElementSetMessagingTimeout(app, 2);
  setFlag(app, "AXManualAccessibility");
  return app;
}

// Walks the windows, depth first, for the controls with these DOM ids → { found: {id: element}, error, windows, web }.
function find(app, wanted) {
  const result = { found: {}, error: 0, windows: 0, web: false };
  const wins = value(app, "AXWindows");
  if (typeof wins === "number") { result.error = wins; return result; }
  result.windows = Number(wins.count);
  let left = wanted.length;
  for (let w = 0; w < wins.count && left > 0; w++) {
    const stack = [wins.objectAtIndex(w)];
    while (stack.length > 0 && left > 0) {
      const el = stack.pop();
      const a = copy(el, WALK);
      if (typeof a === "number") {
        if (a === NO_AX || a === CANNOT) { result.error = a; return result; }
        continue;
      }
      visited++;
      const role = str(a.objectAtIndex(0)), id = str(a.objectAtIndex(2));
      if (role === "AXWebArea") result.web = true;
      if (id !== "" && wanted.indexOf(id) >= 0 && !result.found[id]) { result.found[id] = el; left--; continue; }
      if (SKIP[role]) continue;
      const kids = a.objectAtIndex(1);
      if (kids.isKindOfClass($.NSArray)) for (let k = kids.count - 1; k >= 0; k--) stack.push(kids.objectAtIndex(k));
    }
  }
  return result;
}
// Finds, and when Teams shows nothing yet, asks it to expose its content (harder the second time) and looks again.
function findExposed(app, wanted) {
  let r = find(app, wanted);
  for (let attempt = 0; attempt < 2 && r.error === 0 && !r.found[wanted[0]] && r.windows > 0 && !r.web; attempt++) {
    setFlag(app, attempt === 0 ? "AXManualAccessibility" : "AXEnhancedUserInterface");
    delay(0.5);
    r = find(app, wanted);
  }
  return r;
}
// → { focused, web } of a window: the element with the keyboard focus, found outside lists, tables and trees only (the
// walk does not go there), and — when that is not found — the window's web area; each or null.
function focusedIn(win) {
  const result = { focused: null, web: null };
  const stack = [win];
  while (stack.length > 0) {
    const el = stack.pop();
    const a = copy(el, FOCUS);
    if (typeof a === "number") continue;
    visited++;
    const role = str(a.objectAtIndex(0));
    if (yes(a.objectAtIndex(2))) { result.focused = el; return result; }
    if (role === "AXWebArea" && !result.web) result.web = el;
    if (SKIP[role]) continue;
    const kids = a.objectAtIndex(1);
    if (kids.isKindOfClass($.NSArray)) for (let k = kids.count - 1; k >= 0; k--) stack.push(kids.objectAtIndex(k));
  }
  return result;
}
// Gives the focus back after a press, when the press took it to the control.
function giveFocusBack(before, target) {
  if (!before) return;
  const back = before.focused || before.web;
  if (!back || (before.focused && before.focused.isEqual(target))) return;
  if (yes(value(target, "AXFocused"))) setFlag(back, "AXFocused");
}
// → on, off, locked (mic) / none (camera) when greyed out, unknown (a label not in LABELS), - when there is no such
// control, or gone when the element is no longer the control.
function stateOf(el, id) {
  if (!el) return "-";
  const a = copy(el, LOOK);
  if (typeof a === "number") return "gone";
  visited++;
  if (str(a.objectAtIndex(0)) !== id) return "gone";
  const label = norm(str(a.objectAtIndex(1)));
  const on = id === MIC ? LABELS.micOn : LABELS.cameraOn, off = id === MIC ? LABELS.micOff : LABELS.cameraOff;
  const enabled = a.objectAtIndex(2);
  if (enabled.isKindOfClass($.NSNumber) && !enabled.boolValue) return id === MIC ? "locked" : "none";
  if (on.indexOf(label) >= 0) return "on";
  if (off.indexOf(label) >= 0) return "off";
  return "unknown";
}
function line(asked, teams, mic, camera) { return asked + " " + teams + " " + mic + " " + camera + " " + visited; }

// One read. cache keeps { app, mic, camera } between the reads of a long-lived reader; a single read gets a fresh {}.
function read(pid, cache) {
  const asked = Date.now();
  if (!cache.app) cache.app = appElement(pid);
  if (cache.mic) {                          // the controls found last time, while they are still the controls
    const mic = stateOf(cache.mic, MIC), camera = cache.camera ? stateOf(cache.camera, CAMERA) : "-";
    if (mic !== "gone" && camera !== "gone") return line(asked, "meeting", mic, camera);
    cache.mic = null; cache.camera = null;
  }
  const r = (cache.waited || cache.once) ? findExposed(cache.app, [MIC, CAMERA]) : find(cache.app, [MIC, CAMERA]);
  if (r.error === NO_AX) return line(asked, "noax", "-", "-");
  if (r.error !== 0) return line(asked, "busy", "-", "-");  // quit or hung: the script sees which through lsappinfo
  if (!r.found[MIC]) {
    cache.waited = r.windows > 0 && !r.web;
    return line(asked, cache.waited ? "wait" : "none", "-", "-");
  }
  cache.waited = false;
  cache.mic = r.found[MIC]; cache.camera = r.found[CAMERA] || null;
  return line(asked, "meeting", stateOf(cache.mic, MIC), stateOf(cache.camera, CAMERA));
}

function press(pid, id, show, expect) {
  const app = appElement(pid);
  // The walk stops once all are found: each id once (the mic twice never counts down to zero, and the walk would go
  // through every window), the other of mic and camera only for the state line after a press of one of them.
  const wanted = id === MIC ? [MIC, CAMERA] : id === CAMERA ? [CAMERA, MIC] : id ? [id, MIC] : [MIC];
  const r = findExposed(app, wanted);
  if (r.error === NO_AX) {
    return ["!The agent needs Accessibility: System Settings → Privacy & Security → Accessibility"];
  }
  if (r.error !== 0) return ["!Microsoft Teams did not answer"];
  if (!r.found[MIC] && !r.found[id]) return ["!Not in a Teams meeting"];
  const target = r.found[id || MIC];
  if (!target) return ["!Teams shows no such control in this meeting now (in a narrow window it may be under More)"];
  if (expect) {               // Share only while not sharing, Stop only while sharing, Leave only as Leave
    const label = norm(str(value(target, "AXDescription")));
    if (LABELS[expect].indexOf(label) < 0) {
      const sharing = LABELS.shareStop.indexOf(label) >= 0, idle = LABELS.shareIdle.indexOf(label) >= 0;
      if (expect === "shareIdle" && sharing) return ["!You are sharing already: hold Share to stop"];
      if (expect === "shareStop" && idle) return ["!You are not sharing"];
      if (expect === "leave") return ["!Teams' hang-up button does something else in this meeting: leave in Teams"];
      return ["!Teams shows a Share button this button does not know"];
    }
  }
  if (show) {
    const win = value(target, "AXWindow");
    if (typeof win !== "number") {
      const minimized = value(win, "AXMinimized");
      if (yes(minimized)) $.AXUIElementSetAttributeValue(win, $("AXMinimized"), $.NSNumber.numberWithBool(false));
      $.AXUIElementPerformAction(win, $("AXRaise"));
      setFlag(win, "AXMain");
    }
    setFlag(app, "AXFrontmost");
    if (!id) return [""];
    delay(0.2);
  }
  const enabled = value(target, "AXEnabled");
  if (typeof enabled !== "number" && !yes(enabled)) return ["!Teams has grayed out this control now"];
  const toggle = id === MIC || id === CAMERA;
  const was = toggle ? stateOf(target, id) : "";
  const win = show ? 0 : value(target, "AXWindow");
  const before = typeof win === "number" ? null : focusedIn(win);
  const e = $.AXUIElementPerformAction(target, $("AXPress"));
  if (e !== 0) return ["!Teams did not take the press (" + e + ")"];
  if (!toggle) {
    if (before) { delay(0.2); giveFocusBack(before, target); }
    return [""];
  }
  // Teams switches the label once the change is made (it waits a moment to fold quick clicks, and greys the camera out
  // while it turns it on or off): the new state once the control says on or off again, changed. Not settled within 2 s:
  // nothing is written, the next read tells.
  let now = was, asked = Date.now();
  for (let i = 0; i < 20 && !(now !== was && (now === "on" || now === "off")); i++) {
    delay(0.1);
    asked = Date.now();
    now = stateOf(target, id);
  }
  giveFocusBack(before, target);
  if (now === was || (now !== "on" && now !== "off")) return [""];
  let other = id === MIC ? stateOf(r.found[CAMERA] || null, CAMERA) : stateOf(r.found[MIC] || null, MIC);
  if (other === "gone") other = "-";
  return ["", asked + " meeting " + (id === MIC ? now + " " + other : other + " " + now) + " " + visited];
}

function run(argv) {
  const mode = argv[0], pid = Number(argv[1]);
  if (!(pid > 0)) { put("!no process id"); return; }
  if (mode === "read") { put(read(pid, { once: true })); return; }
  if (mode === "press") {
    const expect = ["shareIdle", "shareStop", "leave"].indexOf(argv[4]) >= 0 ? argv[4] : "";
    press(pid, argv[2] === "-" ? "" : argv[2], argv[3] === "show", expect).forEach(put);
    return;
  }
  if (mode !== "loop") { put("!unknown mode " + mode); return; }
  const period = Number(argv[2]) || 1, idle = Number(argv[3]) || 5;
  const until = Date.now() + (Number(argv[4]) || 1800) * 1000;
  const cache = {};
  let recheck = 0;          // a scan can miss the toolbar once (Teams mid-update): "none" right after a meeting is looked
  while (Date.now() < until) {     // at again after 1 s, twice, before the idle pace (the script waits for 3 in a row)
    const text = read(pid, cache);
    put(text);
    const teams = text.split(" ")[1];
    if (teams === "off" || teams === "noax") return;
    const quick = teams === "wait" || teams === "busy" || (teams === "none" && recheck-- > 0);
    if (teams === "meeting") recheck = 2;
    delay(teams === "meeting" ? period : quick ? 1 : idle);
  }
}
JS
  return 0
}
