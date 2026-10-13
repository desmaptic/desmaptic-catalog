# Zoom › the meeting buttons' shared part: $zoom_ax, a JavaScript for Automation program that reads and presses Zoom's
# menus and its meeting window through the Accessibility API itself — no Apple events, so no Automation question ever
# (reading or pressing), only the Accessibility Desmaptic Agent already has. It never launches Zoom: it asks macOS for the
# running Zoom by bundle id and returns "closed" when there is none. Functions and data only; the button's own line comes
# first and a script after this one runs it (app.json):
#   "mode=mic\n@file:meeting/ax.zsh\n@file:meeting/live.zsh"          — the live state (live.zsh)
#   "action=press item=onMuteAudio:\n@file:meeting/ax.zsh\n@file:meeting/press.zsh"   — a tap (press.zsh)
#   "action=key key=raise-hand\n@file:meeting/ax.zsh\n@file:meeting/press.zsh"       — a shortcut (press.zsh)
#
# What Zoom 7.0.5 (81138) has, read from its bundle and from the running app (2026-09-27):
# - While a meeting runs, Zoom adds a Meeting menu next to its app menu (ZMMeetingMenuMgr) and a View menu after it
#   (ZMViewMenuMgr); outside a meeting neither exists. Their items have no identifier of their own, so AppKit reports
#   each item's action as its AXIdentifier — onMuteAudio:, onMuteVideo:, onShare:, onSwitchViewMode:,
#   onSwitchFullscreen:, onSwitchMinimalVideo:, onCopyInviteLink:, onManageParticipants:, onChat:, onCloudRecord:,
#   onLocalRecord: — the same in every language, so an item is found by it. Their targets are Zoom's menu managers, not
#   the focused window: a press works with Zoom in the background.
# - The two record items (ZMMeetingMenuMgr's menuItemCloudRecord and menuItemLocalRecord, read from zVideoUI; not yet seen
#   in a live meeting) read "Record to the cloud" and "Record to this computer" (or "Record", "Record to host's account",
#   "…with Revenue Accelerator") and turn into "Stop recording", "Pause/stop recording" or "Resume/stop recording" while
#   Zoom records, or into "Request to record to this computer" for a participant without leave. Only a start title is
#   pressed: a stop title refuses as recording, any other title refuses too — a tap never stops, pauses or asks the host.
#   An item Zoom leaves out (no cloud recording on the account) or greys out (the host does not allow it) refuses as well.
#   Zoom may ask before it records (the host's disclaimer) or refuse in a dialog (a minimized meeting window): when the
#   item has not turned into a stop title within a second of the press, Zoom comes forward with its meeting window.
# - Zoom renames the items with the state (ZMMeetingMenuMgr's validateMenuItem: calls updateMenuItemMuteAudio,
#   …MuteVideo, …Share — seen in zVideoUI — and AppKit validates an item as it is read): "Mute audio" while it hears
#   you, "Unmute audio" while you are muted, "Join audio" with no audio connected (the same item), "Mute/Unmute
#   telephone" when you dialled in; "Stop video" / "Start video"; "Stop share" / "Start share". So one menu read tells
#   all three states. The names below are every language Zoom ships (Resources/<lang>.lproj/Localizable.strings), plus
#   the Title Case English of older versions.
# - The meeting window is titled "Zoom Meeting" or "Zoom Webinar" (…Title_148329, with a suffix sometimes). With Stage
#   Manager on, a window outside the stage in front is missing from the app's AXWindows (none at all while a meeting ran,
#   2026-09-27) but is still its AXMainWindow / AXFocusedWindow, so it is looked for there too.
# - Raise hand and the reactions are in no menu, and the meeting window's controls are not in its Accessibility tree
#   while they are hidden (the window held 8 elements, none of them a control of the meeting): only Zoom's shortcuts
#   reach them — ⌥Y Raise/lower hand, ⌥⌘4 clapping hands, ⌥⌘5 thumbs up, ⌥⌘6 love/heart. Zoom keeps a shortcut as a
#   letter and finds its key on the keyboard layout (ZMHotkeyCombo's hotkeyLetter and keyCodeForCurrentKeyboardLayout,
#   UCKeyTranslate in Prism.framework), as Desmaptic Agent does for a keystroke button, so "key" does the same: the key
#   that types the character on the Mac's ASCII-capable layout (the ⌘ table when ⌘ is held), the US position when none
#   does (a digit on AZERTY). A script cannot hand a key to the agent, so it posts the key itself, the way the agent does.
#   The layout functions are loaded by "key" alone (about 11 ms more of osascript), never by a live read.
#
# Modes (the arguments; data never goes into the program text):
#   state          → one line: "closed" (Zoom is not running), "idle" (no meeting), "<mic> <video> <share>" with each
#                    on | off | none | unknown (none: the item is missing — no audio joined, hidden for your role),
#                    or "!ax" (no Accessibility), "!busy" (Zoom did not answer within 2 s)
#   serve          → the same, one line for every line "state" read on stdin; ends by itself after 600 answers
#   press <id>     → presses the Meeting or View menu item with that identifier: "ok", or !closed !idle !missing
#                    !greyed !recording (a record item while Zoom records) !norecord (a record item with a title that
#                    starts no recording) !ax !busy; opening a panel, a share or the audio choice brings Zoom forward,
#                    and so does a record press Zoom has not started recording on within a second
#   window show    → brings the meeting window forward: "ok", or !closed !idle !nowindow !ax !busy
#   window leave   → the same, then presses the window's close button: Zoom asks what to do (host: end for all or
#                    leave) unless you turned "Ask me to confirm when I leave a meeting" off
#   key <c> <us> <mods> → presses a shortcut in the meeting window: <c> the character ("y", "5"), <us> its US key code,
#                    <mods> "option" or "option,command". Only while Zoom is in front with its meeting window focused —
#                    asked of Zoom itself, for up to half a second, just before the key: "ok", or !closed !idle !behind
#                    !ax !busy. It never brings Zoom forward itself ("window show" does, press.zsh runs it first).
#
# One read (state) walks: the app element → AXMenuBar → its items → the menu of item 3 (where Zoom puts Meeting) → its
# items → AXIdentifier of each until the three are found (items 10, 11, 13 of 18) → their AXTitle: about 21 Accessibility
# calls, a few milliseconds against Zoom in a meeting. Outside a meeting it reads the titles of the menu bar's items
# instead and stops.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
read -r -d '' zoom_ax <<'JS'
ObjC.import("AppKit");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCreateSystemWide", ["id", []]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementSetAttributeValue", ["int", ["id", "id", "id"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);
ObjC.bindFunction("AXUIElementSetMessagingTimeout", ["int", ["id", "float"]]);

const MEETING_MENU = ["Meeting", "Reunión", "Réunion", "Rapat", "Riunione", "ミーティング", "회의", "Vergadering", "Spotkanie", "Reunião", "Конференция", "Möte", "Toplantı", "Cuộc họp", "会议", "會議"];
const MIC_ON = ["Mute Audio", "Audio stummschalten", "Mute audio", "Silenciar audio", "Désactiver le son", "Bisukan audio", "Disattiva audio", "オーディオのミュート", "오디오 음소거", "Audio dempen", "Wycisz dźwięk", "Desativar áudio", "Выключить звук", "Inaktivera ljud", "Sesi kapat", "Tắt tiếng âm thanh", "静音", "靜音", "Mute Telephone", "Telefon stummschalten", "Mute telephone", "Silenciar teléfono", "Couper le micro du téléphone", "Bisukan telepon", "Disattiva audio del telefono", "電話のミュート", "전화기 음소거", "Telefoon dempen", "Wycisz telefon", "Desativar som do telefone", "Выключить звук телефона", "Inaktivera telefonens mikrofon", "Telefonu sessize al", "Tắt tiếng điện thoại", "电话静音", "電話靜音"];
const MIC_OFF = ["Unmute Audio", "Stummschaltung für Audio aufheben", "Unmute audio", "Reactivar audio", "Réactiver le son", "Bunyikan audio", "Attiva audio", "オーディオのミュート解除", "오디오 음소거 해제", "Audio dempen opheffen", "Wyłącz wyciszenie dźwięku", "Ativar áudio", "Включить звук", "Aktivera ljud", "Sesi aç", "Bỏ tắt tiếng âm thanh", "解除静音", "解除靜音", "Unmute Telephone", "Telefon-Stummschaltung aufheben", "Unmute telephone", "Cancelar silenciar teléfono", "Rétablir le micro du téléphone", "Bunyikan telepon", "Attiva audio del telefono", "電話のミュート解除", "전화기 음소거 해제", "Telefoon dempen opheffen", "Wyłącz wyciszenie telefonu", "Ativar som do telefone", "Включить звук телефона", "Aktivera telefonens mikrofon", "Telefonun sesini aç", "Bỏ tắt tiếng điện thoại", "解除电话静音", "解除電話靜音"];
const JOIN_AUDIO = ["Join Audio", "An Audio teilnehmen", "Join audio", "Conectar audio", "Participer à l’audio", "Bergabung ke audio", "Connettiti all’audio", "オーディオに接続", "오디오 연결", "Deelnemen aan audio", "Dołącz do poł. Głos.", "Conectar áudio", "Подключить звук", "Delta via ljud", "Sese katıl", "Kết nối âm thanh", "连接语音", "加入音訊"];
const VIDEO_ON = ["Stop Video", "Video beenden", "Stop video", "Detener vídeo", "Arrêter la vidéo", "Hentikan video", "Disattiva video", "ビデオをオフにする", "비디오 중지", "Zatrzymaj wideo", "Interromper vídeo", "Остановить видео", "Stoppa video", "Videoyu durdur", "Dừng video", "停止视频", "停止視訊"];
const VIDEO_OFF = ["Start Video", "Video starten", "Start video", "Iniciar vídeo", "Démarrer la vidéo", "Mulai video", "Avvia video", "ビデオをオンにする", "비디오 시작", "Uruchom wideo", "Начать видео", "Starta video", "Videoyu başlat", "Bắt đầu video", "开启视频", "開啟視訊"];
const SHARE_ON = ["Stop Share", "Freigabe stoppen", "Stop share", "Dejar de compartir", "Arrêter le partage", "Hentikan berbagi", "Interrompi condivisione", "共有の停止", "공유 중지", "Delen stoppen", "Zatrzymaj udostępnianie", "Interromper compartilhamento", "Остановить совместное использование", "Stoppa delning", "Paylaşımı durdur", "Dừng chia sẻ", "停止共享", "停止分享"];
const SHARE_OFF = ["Start Share", "Share starten", "Start share", "Iniciar compartir", "Commencer à partager", "Mulai berbagi", "Avvia condivisione", "共有の開始", "공유 시작", "Delen starten", "Rozpocznij udostępnianie", "Iniciar compartilhamento", "Начать совместное использование", "Starta delning", "Paylaşımı başlat", "Bắt đầu chia sẻ", "开始共享", "開始分享"];
// View › Show participants / Show chat: the panel is closed and the press opens it.
const SHOW_PANEL = ["Show participants", "Teilnehmer anzeigen", "Mostrar participantes", "Afficher les participants", "Tampilkan peserta", "Mostra partecipanti", "参加者を表示", "참가자 표시", "Deelnemers weergeven", "Pokaż uczestników", "Показать участников", "Visa deltagare", "Katılımcıları göster", "Hiển thị người tham gia", "显示参会者", "顯示與會者", "Show Chat", "Show chat", "Chat anzeigen", "Mostrar chat", "Afficher le chat", "Tampilkan obrolan", "Mostra chat", "チャットを表示", "채팅 표시", "Chat weergeven", "Pokaż czat", "Exibir chat", "Показать чат", "Visa chatt", "Sohbeti göster", "Hiển thị cuộc trò chuyện", "显示聊天", "顯示聊天"];
// Meeting › Record to the cloud / Record to this computer: a record item is pressed only under one of Zoom's own titles
// that start a recording (to the cloud, this computer, the host's account, with Revenue Accelerator, or plain Record).
const RECORD_START = ["Record to the Cloud", "Record to the cloud", "In der Cloud aufzeichnen", "Grabar en la nube", "Enregistrement dans le cloud", "Rekam ke cloud", "Registra nel cloud", "クラウドにレコーディングする", "클라우드에 녹화", "Opnemen in de cloud", "Nagrywaj na chmurę", "Gravado na nuvem", "Запись в облако", "Spela in till molnet", "Buluta kaydet", "Ghi vào đám mây", "云录制", "雲端錄製", "Record to this computer", "Auf diesem Computer aufzeichnen", "Grabar en este equipo", "Enregistrer sur cet ordinateur", "Rekam ke komputer ini", "Registra su questo computer", "このコンピュータにレコーディングする", "이 컴퓨터에 녹화", "Opnemen op deze computer", "Nagraj na ten komputer", "Gravar neste computador", "Записывать на этот компьютер", "Spela in på denna dator", "Bu bilgisayara kaydet", "Ghi vào máy tính này", "录制到本电脑", "錄製到本電腦", "Record to host's account", "Im Konto des Hosts aufzeichnen", "Grabación en la cuenta del anfitrión", "Enregistrer sur le compte de l’hôte", "Rekam ke akun host", "Registra nell’account dell’organizzatore", "ホストのアカウントにレコーディングする", "호스트의 계정에 녹화", "Opnemen op het account van de host", "Nagraj na koncie prowadzącego", "Gravar na conta do anfitrião", "Запись в учетную запись организатора", "Spela in på värdens konto", "Oturum sahibinin hesabına kaydet", "Ghi vào tài khoản của người chủ trì", "录制到主持人的账户", "錄製至主持人的帳戶", "Record to the cloud with Revenue Accelerator", "Mit Revenue Accelerator in der Cloud aufzeichnen", "Grabar en la nube con Revenue Accelerator", "Enregistrer dans le cloud avec Revenue Accelerator", "Rekam ke cloud dengan Revenue Accelerator", "Registra nel cloud con Revenue Accelerator", "Revenue Accelerator を使用してクラウドにレコーディング", "Revenue Accelerator를 사용하여 클라우드에 녹화", "Opnemen in de cloud met Revenue Accelerator", "Nagrywaj w chmurze za pomocą Revenue Accelerator", "Gravar na nuvem com o Revenue Accelerator", "Запись в облако с помощью Revenue Accelerator", "Spela in till molnet med Revenue Accelerator", "Revenue Accelerator ile buluta kaydet", "Ghi lại trên đám mây bằng Revenue Accelerator", "使用Revenue Accelerator录制到云端", "使用Revenue Accelerator錄製至雲端", "Record", "Aufzeichnen", "Grabar", "Enregistrer", "Rekam", "Registra", "レコーディング", "녹화", "Opnemen", "Nagrywaj", "Gravar", "Запись", "Spela in", "Kaydet", "Ghi", "录制", "錄製", "Nagranie", "Kayıt"];
// …and the titles it takes while Zoom records (stop, pause, resume; a stop with a countdown): a press would stop or pause.
const RECORD_STOP = ["Stop Recording", "Stop recording", "Aufzeichnung stoppen", "Detener grabación", "Arrêter l’enregistrement", "Hentikan perekaman", "Interrompi registrazione", "レコーディングを停止", "녹화 중지", "Opname stoppen", "Zatrzymaj nagrywanie", "Interromper gravação", "Остановить запись", "Stoppa inspelning", "Kaydı durdur", "Dừng ghi", "停止录制", "停止錄製", "Resume/Stop Recording", "Resume/stop recording", "Aufzeichnung fortsetzen/beenden", "Reanudar/detener grabación", "Reprendre/arrêter l’enregistrement", "Lanjut/berhenti rekam", "Riprendi/arresta la registrazione", "レコーディングを再開／停止", "녹화 다시 시작/중지", "Opname hervatten/stoppen", "Wznów/zatrzymaj nagrywanie", "Retomar/interromper gravação", "Продолжить/остановить запись", "Fortsätt/stoppa inspelning", "Kaydı devam ettir/durdur", "Tiếp tục/dừng ghi", "继续/停止录制", "繼續/停止錄製", "Pause/Stop Recording", "Pause/stop recording", "Aufzeichnung anhalten/beenden", "Pausar/detener grabación", "Suspendre/arrêter l’enregistrement", "Jeda/berhenti rekam", "Metti in pausa/arresta la registrazione", "レコーディングを一時停止／停止", "녹화 일시 중지/중지", "Opname pauzeren/stoppen", "Wstrzymaj/zatrzymaj nagrywanie", "Pausar/interromper gravação", "Пауза/остановить запись", "Pausa/stoppa inspelning", "Kaydı duraklat/durdur", "Tạm dừng/dừng ghi", "暂停/停止录制", "暫停/停止錄製", "Pause Recording", "Pause recording", "Aufzeichnung anhalten", "Pausar grabación", "Suspendre l’enregistrement", "Jeda perekaman", "Metti in pausa la registrazione", "レコーディングを一時停止", "녹화 일시 중지", "Opname pauzeren", "Wstrzymaj nagrywanie", "Pausar gravação", "Приостановить запись", "Pausa inspelning", "Kaydı duraklat", "Tạm dừng ghi", "暂停录制", "暫停錄製", "Resume Recording", "Resume recording", "Aufzeichnung fortsetzen", "Reanudar grabación", "Reprendre l’enregistrement", "Lanjutkan perekaman", "Riprendi la registrazione", "レコーディングを再開", "녹화 다시 시작", "Opname hervatten", "Wznów nagrywanie", "Retomar gravação", "Продолжить запись", "Fortsätt inspelning", "Kaydı devam ettir", "Tiếp tục ghi", "继续录制", "繼續錄製", "녹음 중지"];
const RECORD_IDS = ["onCloudRecord:", "onLocalRecord:"];
function isRecording(title) { return RECORD_STOP.some(name => title.startsWith(name)); }
// The meeting window's title starts with one of these (Zoom may add a suffix).
const MEETING_WINDOW = ["Zoom Meeting", "Reunión de Zoom", "Réunion Zoom", "Riunione Zoom", "Zoom ミーティング", "Zoom 회의", "Zoom-vergadering", "Spotkanie Zoom", "Reunião Zoom", "Конференция Zoom", "Zoom-möte", "Zoom Toplantısı", "Cuộc họp Zoom", "Zoom会议", "Zoom會議", "Zoom-Webinar", "Zoom Webinar", "Seminario web de Zoom", "Webinaire Zoom", "Webinar Zoom", "Zoom ウェビナー", "Zoom 웨비나", "Webinar w Zoomie", "Вебинар Zoom", "Zoom Web Semineri", "Hội thảo trực tuyến Zoom", "Zoom网络研讨会", "Zoom網路研討會"];
// Items only the Meeting menu has: how it is told apart from the others without its name.
const MEETING_IDS = ["onSwitchFullscreen:", "onFloatOnTop:", "onSwitchMinimalVideo:", "onSwitchViewMode:", "onMuteAll:", "onUnmuteAll:", "onMuteAudio:", "onMuteVideo:"];

// The Accessibility calls. An error other than "no Accessibility" (-25211) or "Zoom did not answer" (-25204) is
// "no such attribute": null. The value is read only after success — reading a Ref() after an error crashes osascript.
function get(element, name) {
  const value = Ref();
  const error = $.AXUIElementCopyAttributeValue(element, $(name), value);
  if (error == 0) return value[0];
  if (error == -25211) throw "ax";
  if (error == -25204) throw "busy";
  return null;
}
function text(element, name) {
  const value = get(element, name);
  if (value === null) return "";
  const s = ObjC.unwrap(value);
  return typeof s == "string" ? s : "";
}
function list(element, name) { const value = get(element, name); return value === null ? [] : value; }
function flag(element, name) { const value = get(element, name); return value !== null && ObjC.unwrap(value) === true; }
function perform(element, action) {
  const error = $.AXUIElementPerformAction(element, $(action));
  if (error == -25211) throw "ax";
  return error;   // -25204 after a press: Zoom took it and is busy (a dialog) — the press happened
}
function set(element, name, value) {
  const error = $.AXUIElementSetAttributeValue(element, $(name), value);
  if (error == -25211) throw "ax";
}

function zoomApp() {
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("us.zoom.xos");
  for (let i = 0; i < apps.count; i++) {
    const app = apps.objectAtIndex(i);
    if (app.finishedLaunching) return $.AXUIElementCreateApplication(app.processIdentifier);
  }
  return null;
}
function itemsOf(top) {
  const menus = list(top, "AXChildren");
  return Number(menus.count) > 0 ? list(menus.objectAtIndex(0), "AXChildren") : [];   // count is a string: "0" is truthy
}
function isMeetingMenu(items) {
  for (let i = 0; i < items.count && i < 6; i++) {
    if (MEETING_IDS.includes(text(items.objectAtIndex(i), "AXIdentifier"))) return true;
  }
  return false;
}
// The Meeting menu — the menu bar's items, its place among them and its own items — or null outside a meeting: where
// Zoom puts it (third in the menu bar) first, then by name.
function meetingMenu(app) {
  const bar = get(app, "AXMenuBar");
  if (bar === null) return null;
  const tops = list(bar, "AXChildren");
  if (tops.count > 2) {
    const items = itemsOf(tops.objectAtIndex(2));
    if (isMeetingMenu(items)) return { tops: tops, index: 2, items: items };
  }
  for (let i = 1; i < tops.count; i++) {
    if (i == 2 || !MEETING_MENU.includes(text(tops.objectAtIndex(i), "AXTitle"))) continue;
    const items = itemsOf(tops.objectAtIndex(i));
    if (isMeetingMenu(items)) return { tops: tops, index: i, items: items };
  }
  return null;
}
function meetingItems(app) { const menu = meetingMenu(app); return menu === null ? null : menu.items; }
// A menu item by its identifier, in the Meeting menu and the View menu right after it and nowhere else: whatever
// another menu may hold under the same action, a press never reaches it. Only identifiers are read on the way.
function findItem(menu, id) {
  for (const i of [menu.index, menu.index + 1]) {
    if (i >= menu.tops.count) continue;
    const items = i == menu.index ? menu.items : itemsOf(menu.tops.objectAtIndex(i));
    for (let j = 0; j < items.count; j++) {
      if (text(items.objectAtIndex(j), "AXIdentifier") == id) return items.objectAtIndex(j);
    }
  }
  return null;
}
function isMeetingWindow(window) {
  const title = text(window, "AXTitle");
  return MEETING_WINDOW.some(name => title == name || title.startsWith(name + " "));
}
function meetingWindow(app) {
  const windows = list(app, "AXWindows");
  let found = null;
  for (let i = 0; i < windows.count; i++) {
    const window = windows.objectAtIndex(i);
    if (!isMeetingWindow(window)) continue;
    if (text(window, "AXSubrole") == "AXStandardWindow") return window;
    if (found === null) found = window;
  }
  if (found !== null) return found;
  // Stage Manager leaves a window outside the stage in front out of AXWindows; Zoom still names it as its main window.
  for (const name of ["AXMainWindow", "AXFocusedWindow"]) {
    const window = get(app, name);
    if (window !== null && isMeetingWindow(window)) return window;
  }
  return null;
}
function bringForward(app, window) {
  if (window !== null) {
    if (flag(window, "AXMinimized")) set(window, "AXMinimized", $.NSNumber.numberWithBool(false));
    perform(window, "AXRaise");
  }
  set(app, "AXFrontmost", $.NSNumber.numberWithBool(true));
}

// After a record press: Zoom renames the item to "Stop recording" once it records. Until it has, within a second, it may
// be asking or explaining in a dialog of its own — the host's "Record this meeting to the cloud?", "Recording cannot
// start if the meeting window is minimized" — or the press may have been held up by one (-25204): Zoom comes forward with
// its meeting window then, so the question is seen and answered on the Mac, not left behind other apps.
function recordStarted(app, id) {
  for (let i = 0; i < 10; i++) {
    delay(0.1);
    const menu = meetingMenu(app);
    const item = menu === null ? null : findItem(menu, id);
    if (item !== null && isRecording(text(item, "AXTitle"))) return true;
  }
  return false;
}
function showZoom(app) {
  try {
    bringForward(app, meetingWindow(app));
  } catch (e) {
    if (e !== "busy") throw e;   // Zoom held up in its dialog: asked once more, then macOS is asked, not Zoom
    set(app, "AXFrontmost", $.NSNumber.numberWithBool(true));
    const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("us.zoom.xos");
    if (apps.count > 0) apps.objectAtIndex(0).activateWithOptions(1);   // NSApplicationActivateAllWindows
  }
}

function state() {
  try {
    const app = zoomApp();
    if (app === null) return "closed";
    const items = meetingItems(app);
    if (items === null) return "idle";
    const titles = { "onMuteAudio:": null, "onMuteVideo:": null, "onShare:": null };
    let left = 3;
    for (let i = 0; i < items.count && left > 0; i++) {
      const item = items.objectAtIndex(i), id = text(item, "AXIdentifier");
      if (id in titles && titles[id] === null) { titles[id] = text(item, "AXTitle"); left--; }
    }
    const word = (title, on, off, none) =>
      title === null || none.includes(title) ? "none" : on.includes(title) ? "on" : off.includes(title) ? "off" : "unknown";
    return word(titles["onMuteAudio:"], MIC_ON, MIC_OFF, JOIN_AUDIO) + " " +
      word(titles["onMuteVideo:"], VIDEO_ON, VIDEO_OFF, []) + " " +
      word(titles["onShare:"], SHARE_ON, SHARE_OFF, []);
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
function press(id) {
  try {
    const app = zoomApp();
    if (app === null) return "!closed";
    const menu = meetingMenu(app);
    if (menu === null) return "!idle";
    const item = findItem(menu, id);
    if (item === null) return "!missing";
    if (!flag(item, "AXEnabled")) return "!greyed";
    const title = text(item, "AXTitle");
    if (RECORD_IDS.includes(id)) {
      if (isRecording(title)) return "!recording";
      if (!RECORD_START.includes(title)) return "!norecord";   // a request to the host, or a title not known
    }
    const error = perform(item, "AXPress");
    if (error != 0 && error != -25204) return "!press " + error;
    if (RECORD_IDS.includes(id)) {
      let started = false;
      if (error == 0) {
        try { started = recordStarted(app, id); } catch (e) { if (e !== "busy") throw e; }   // pressed all the same
      }
      if (!started) showZoom(app);
      return "ok";
    }
    // What the press opens on the Mac is only of use in front: a panel of the meeting window, the share picker, the
    // choice of audio. Nothing else brings Zoom forward — muting from another app leaves you in that app.
    if (SHOW_PANEL.includes(title)) bringForward(app, meetingWindow(app));
    else if (SHARE_OFF.includes(title) || JOIN_AUDIO.includes(title)) bringForward(app, null);
    return "ok";
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
function windowAction(what) {
  try {
    const app = zoomApp();
    if (app === null) return "!closed";
    if (meetingItems(app) === null) return "!idle";
    const window = meetingWindow(app);
    if (window === null) return "!nowindow";
    bringForward(app, window);
    if (what == "leave") {
      const close = get(window, "AXCloseButton");
      if (close === null) return "!nowindow";
      const error = perform(close, "AXPress");
      if (error != 0 && error != -25204) return "!press " + error;
    }
    return "ok";
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}

// The shortcut keys (mode "key").
const FLAGS = { shift: 0x20000, control: 0x40000, option: 0x80000, command: 0x100000 };   // kCGEventFlagMask…
// Where a character's key is looked for, as Desmaptic Agent looks (KeyCodeMapper): the US printable positions, then the
// ISO section key and the JIS keys. Never the keypad: ⌘ + keypad 5 is not ⌘5.
const KEYS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
  30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50, 10, 93, 94];
function loadKeyFunctions() {
  ObjC.import("CoreGraphics");
  ObjC.import("Carbon");
  ObjC.bindFunction("UCKeyTranslate", ["int", ["void *", "unsigned short", "unsigned short", "unsigned int",
    "unsigned int", "unsigned int", "void *", "unsigned long", "void *", "void *"]]);
  ObjC.bindFunction("LMGetKbdType", ["unsigned char", []]);
  ObjC.bindFunction("CGPreflightPostEventAccess", ["bool", []]);
}
// The Mac's ASCII-capable layout (the one macOS matches shortcuts through while a Cyrillic or Greek source is on), as
// its key data, or null.
function asciiLayout() {
  const source = $.TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
  if (!source) return null;
  const data = $.TISGetInputSourceProperty(source, $.kTISPropertyUnicodeKeyLayoutData);
  return data ? ObjC.castRefToObject(data) : null;
}
// The key that types `character` on `layout` (its ⌘ table when ⌘ is held), or `usCode` when no key does.
function keyTyping(layout, keyboard, character, usCode, withCommand) {
  const typed = code => {
    const dead = $.NSMutableData.dataWithLength(4), length = $.NSMutableData.dataWithLength(8);
    const buffer = $.NSMutableData.dataWithLength(8);   // 4 UTF-16 units, zeroed
    // kUCKeyActionDown, (cmdKey >> 8) & 0xFF or no modifiers, kUCKeyTranslateNoDeadKeysMask — as the agent reads it.
    const status = $.UCKeyTranslate(layout.bytes, code, 0, withCommand ? 1 : 0, keyboard, 1, dead.mutableBytes, 4,
      length.mutableBytes, buffer.mutableBytes);
    if (status != 0) return "";
    const s = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(buffer, $.NSUTF16LittleEndianStringEncoding));
    return typeof s == "string" ? s.replace(/\0+$/, "").toLowerCase() : "";
  };
  if (typed(usCode) === character) return usCode;
  for (const code of KEYS) if (typed(code) === character) return code;
  return usCode;
}
// Posts a key with its modifiers as Desmaptic Agent posts a keystroke button's: the modifiers, the key down and up, the
// modifiers released, to the session — which hands them to the app in front.
function postKey(code, flags) {
  const source = $.CGEventSourceCreate(1);                   // kCGEventSourceStateHIDSystemState
  const send = (key, down, modifiersOnly, eventFlags) => {
    const event = $.CGEventCreateKeyboardEvent(source, key, down);
    if (modifiersOnly) $.CGEventSetType(event, 12);          // kCGEventFlagsChanged
    $.CGEventSetFlags(event, eventFlags);
    $.CGEventPost(2, event);                                 // kCGAnnotatedSessionEventTap
  };
  send(0, true, true, flags);
  delay(0.01);
  send(code, true, false, flags);
  delay(0.03);
  send(code, false, false, flags);
  send(0, false, true, 0);
}
function pressKey(character, usCode, modifiers) {
  try {
    const app = zoomApp();
    if (app === null) return "!closed";
    if (meetingItems(app) === null) return "!idle";
    loadKeyFunctions();
    if (!$.CGPreflightPostEventAccess()) return "!ax";
    let flags = 0;
    for (const name of modifiers.split(",")) {
      if (!(name in FLAGS)) return "!error modifier " + name;
      flags |= FLAGS[name];
    }
    const layout = asciiLayout();
    const code = layout === null ? usCode :
      keyTyping(layout, $.LMGetKbdType(), character, usCode, (flags & FLAGS.command) != 0);
    // Last, right before the key: Zoom in front with its meeting window focused, asked of Zoom itself — the key never
    // goes to another app, nor to another Zoom window (a chat, the settings).
    for (let tries = 0; ; tries++) {
      const focused = get(app, "AXFocusedWindow");
      if (flag(app, "AXFrontmost") && focused !== null && isMeetingWindow(focused)) break;
      if (tries == 10) return "!behind";
      delay(0.05);
    }
    postKey(code, flags);
    return "ok";
  } catch (e) {
    return (e === "ax" || e === "busy") ? "!" + e : "!error " + e;
  }
}
function serve() {
  const input = $.NSFileHandle.fileHandleWithStandardInput;
  const output = $.NSFileHandle.fileHandleWithStandardOutput;
  let buffer = "";
  for (let answered = 0; answered < 600; ) {
    const end = buffer.indexOf("\n");
    if (end < 0) {
      const data = input.availableData;
      if (data.length == 0) return;
      buffer += $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
      continue;
    }
    const line = buffer.slice(0, end);
    buffer = buffer.slice(end + 1);
    if (line != "state") continue;
    output.writeData($(state() + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
    answered++;
  }
}
function run(argv) {
  $.AXUIElementSetMessagingTimeout($.AXUIElementCreateSystemWide(), 2);   // for every call: 2 s, not 6
  switch (argv[0]) {
    case "state": return state();
    case "serve": serve(); return;
    case "press": return argv[1] ? press(argv[1]) : "!error press needs an item";
    case "window": return (argv[1] == "show" || argv[1] == "leave") ? windowAction(argv[1]) : "!error window " + argv[1];
    case "key":
      return (argv.length == 4 && argv[1].length == 1 && /^[0-9]+$/.test(argv[2]))
        ? pressKey(argv[1].toLowerCase(), parseInt(argv[2], 10), argv[3]) : "!error key needs <c> <us> <mods>";
    default: return "!error mode " + argv[0];
  }
}
JS
