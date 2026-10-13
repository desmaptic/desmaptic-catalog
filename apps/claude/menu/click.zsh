# Claude › Next Chat and Previous Chat, Back and Forward, the Code session's panes (Terminal, Changes, Preview, Files),
# the Command Palette and Reopen Closed Session: an item of Claude's Go, View or File menu, clicked through System
# Events. Next and Previous (⇧⌘] / ⇧⌘[) and Back and Forward (⌘[ / ⌘]) sit on bracket keys that German, French,
# Spanish, Nordic, Swiss and other layouts type only with Option or Shift, so the keystroke misses there; the preview
# pane is "Browser" (⇧⌘B) or "Preview" (⇧⌘P) depending on Claude's version. The pane items (⌘J, ⇧⌘D, ⇧⌘F, ⇧⌘B or ⇧⌘P)
# are greyed out unless Claude's main window shows a Code session that has that pane (not every kind of session has a
# terminal) and no other Claude window (Settings, Quick Entry) has the focus, and a key pressed into a greyed-out item
# does nothing and says nothing; clicked, the button refuses and says why. Claude's page also matches these keys by
# position (KeyboardEvent.code), so on Dvorak or Colemak the key the agent presses for ⌘J misses. The menu item works on
# every layout, wherever the focus is in Claude's window. View › Command Palette… (⌘K) is always there and brings up
# Claude's main window first. File › Reopen Closed Session (⇧⌘T) is in the menu only while the main window shows
# Claude Code and no other Claude window has the focus, and greyed out while no closed session is left to reopen; the
# button says which. Claude names its menus in its own language, so the script knows every name in each language Claude
# ships (its Resources/<lang>.json, taken by string key: 43 languages in 2.31226.1, and the names of 2.7032.0 and
# 2.19675.0 kept; no name of one item or menu is another's in any language): Next and Previous are "Chat" in Chat,
# "Task" in Cowork and "Session" in Code, a pane item is "Show …" or "Hide …". The item acts on Claude's focused
# window, so the script refuses while Claude is not in front, and says so when the item is greyed out. It needs
# Accessibility, and the first tap brings up the macOS question about controlling System Events. It never launches
# Claude. Every button's command is one line that names the item, then this file (app.json):
#   "action=next\n@file:menu/click.zsh"   — next, previous, back, forward, terminal, changes, files, preview, palette
#                                           or reopen.
# What the refusal says when the item is greyed out (greyed) or not in the menu at all (absent): for the panes, where
# Claude offers them.
code="Claude offers it only in its main window, in a Code session that has this pane" absent=
case $action in
  next)
    menus=(Go) label='Go › Next Chat' greyed=
    names=(
      "Next Chat" "Next Task" "Next Session" "Nächster Chat" "Nächste Aufgabe" "Nächste Sitzung" "Chat siguiente"
      "Tarea siguiente" "Sesión siguiente" "Conversation suivante" "Tâche suivante" "Session suivante" "अगली चैट"
      "अगला टास्क" "अगला सेशन" "Chat Berikutnya" "Tugas Berikutnya" "Sesi Berikutnya" "Chat successiva"
      "Attività successiva" "Sessione successiva" "次のチャット" "次のタスク" "次のセッション" "다음 채팅" "다음 작업" "다음 세션" "Próximo chat"
      "Próxima tarefa" "Próxima sessão" "ቀጣይ ውይይት" "अगिला चैट" "পরবর্তী চ্যাট" "Næste chat" "Seuraava keskustelu"
      "Susunod na chat" "આગલી ચેટ" "Taɗi na gaba" "Nkata ọzọ" "ಮುಂದಿನ ಚಾಟ್" "അടുത്ത ചാറ്റ്" "पुढील चॅट" "Neste samtale"
      "Volgende chat" "Kukambirana kotsatira" "Haasawa itti aanu" "Ikiyago gikurikira" "Следующий чат"
      "Ikiganiro gikurikira" "Wadahadalka xiga" "Nästa chatt" "Mazungumzo yanayofuata" "அடுத்த அரட்டை" "తదుపరి చాట్"
      "แชทถัดไป" "Sonraki sohbet" "Наступний чат" "Đoạn chat tiếp theo" "Waxtaan bu ci topp" "Lọ sí ìfọ̀rọ̀wérọ̀ tó kàn"
      "下一个对话" "下一則對話" "ቀጣይ ተግባር" "अगिला टास्क" "পরবর্তী টাস্ক" "Næste opgave" "Seuraava tehtävä" "Susunod na task"
      "આગળનો ટાસ્ક" "Ɗawainiya ta gaba" "Ọrụ na-esote" "ಮುಂದಿನ ಕಾರ್ಯ" "അടുത്ത ടാസ്‌ക്" "पुढील कार्य" "Neste oppgave"
      "Volgende taak" "Ntchito yotsatira" "Hojii itti aanu" "Umurimo ukurikira" "Следующая задача" "Hawsha xigta"
      "Nästa uppgift" "Kazi inayofuata" "அடுத்த பணி" "తదుపరి టాస్క్" "งานถัดไป" "Sonraki görev" "Наступне завдання"
      "Tác vụ tiếp theo" "Liggéey bi ci topp" "Iṣẹ́ tó kàn" "下一个任务" "下一個任務" "ቀጣይ ክፍለ ጊዜ" "अगिला सेशन" "পরবর্তী সেশন"
      "Næste session" "Seuraava istunto" "Susunod na session" "આગલું સેશન" "Zama na gaba" "Nnọkọ na-esote"
      "ಮುಂದಿನ ಸೆಷನ್" "അടുത്ത സെഷൻ" "पुढील सेशन" "Neste økt" "Volgende sessie" "Gawo lotsatira"
      "Gara seeshinii itti aanutti darbi" "Seshiyo ikurikira" "Следующая сессия" "Session ikurikira" "Fadhiga xiga"
      "Nästa session" "Kipindi kifuatacho" "அடுத்த அமர்வு" "తదుపరి సెషన్" "เซสชันถัดไป" "Sonraki oturum"
      "Наступна сесія" "Phiên tiếp theo" "Seans bi ci topp" "Lọ sí ìgbà iṣẹ́ tó kàn" "下一个会话" "下一個工作階段"
      "अगली चैट पर जाएं" "Chat berikutnya" "Nkata na-esote" "ಮುಂದಿನ ಚಾಟ್‌ಗೆ ಹೋಗಿ" "അടുത്ത ചാറ്റിലേക്ക് പോകുക"
      "Próxima conversa" "తదుపరి చాట్‌కు వెళ్లండి" "ወደ ቀጣዩ ተግባር ይሂዱ" "अगले टास्क पर जाएं" "Tugas berikutnya"
      "ಮುಂದಿನ ಕಾರ್ಯಕ್ಕೆ ಹೋಗಿ" "അടുത്ത ടാസ്‌ക്കിലേക്ക് പോകുക" "తదుపరి టాస్క్‌కు వెళ్లండి" "આગલા સેશન પર જાઓ"
      "अगले सेशन पर जाएं" "Sesi berikutnya" "അടുത്ത സെഷനിലേക്ക് പോകുക" "తదుపరి సెషన్‌కు వెళ్లండి"
    ) ;;
  previous)
    menus=(Go) label='Go › Previous Chat' greyed=
    names=(
      "Previous Chat" "Previous Task" "Previous Session" "Vorheriger Chat" "Vorherige Aufgabe" "Vorherige Sitzung"
      "Chat anterior" "Tarea anterior" "Sesión anterior" "Conversation précédente" "Tâche précédente"
      "Session précédente" "पिछली चैट" "पिछला टास्क" "पिछला सेशन" "Chat Sebelumnya" "Tugas Sebelumnya" "Sesi Sebelumnya"
      "Chat precedente" "Attività precedente" "Sessione precedente" "前のチャット" "前のタスク" "前のセッション" "이전 채팅" "이전 작업" "이전 세션"
      "Tarefa anterior" "Sessão anterior" "ቀዳሚ ውይይት" "पिछला चैट" "পূর্ববর্তী চ্যাট" "Forrige chat"
      "Edellinen keskustelu" "Nakaraang chat" "પાછલી ચેટ" "Taɗin da ya gabata" "Nkata gara aga" "ಹಿಂದಿನ ಚಾಟ್"
      "മുൻ ചാറ്റ്" "मागील चॅट" "Forrige samtale" "Vorige chat" "Kukambirana kwapitako" "Haasawa duraanii"
      "Ikiyago c’imbere" "Предыдущий чат" "Ikiganiro kibanza" "Wadahadalkii hore" "Föregående chatt"
      "Mazungumzo yaliyotangulia" "முந்தைய அரட்டை" "మునుపటి చాట్" "แชทก่อนหน้า" "Önceki sohbet" "Попередній чат"
      "Đoạn chat trước" "Waxtaan bu jiitu" "Ìfọ̀rọ̀wérọ̀ tó ṣáájú" "上一个对话" "上一個對話" "ቀዳሚ ተግባር" "পূর্ববর্তী টাস্ক"
      "Forrige opgave" "Edellinen tehtävä" "Nakaraang task" "પહેલાંનો ટાસ્ક" "Ɗawainiyar da ta gabata" "Ọrụ gara aga"
      "ಹಿಂದಿನ ಕಾರ್ಯ" "മുമ്പത്തെ ടാസ്‌ക്" "मागील कार्य" "Forrige oppgave" "Vorige taak" "Ntchito yapitayo"
      "Hojii duraanii" "Umurimo ubanza" "Предыдущая задача" "Hawsha hore" "Föregående uppgift" "Kazi iliyotangulia"
      "முந்தைய பணி" "మునుపటి టాస్క్" "งานก่อนหน้า" "Önceki görev" "Попереднє завдання" "Tác vụ trước" "Liggéey bi jiitu"
      "Iṣẹ́ tó ṣáájú" "上一个任务" "上一個任務" "ቀዳሚ ክፍለ ጊዜ" "পূর্ববর্তী সেশন" "Forrige session" "Edellinen istunto"
      "Nakaraang session" "પાછલું સેશન" "Zaman da ya gabata" "Nnọkọ gara aga" "ಹಿಂದಿನ ಸೆಷನ್" "മുമ്പത്തെ സെഷൻ"
      "मागील सेशन" "Forrige økt" "Vorige sessie" "Gawo lapitalo" "Seeshinii duraanii" "Igihe c’akazi giheruka"
      "Предыдущая сессия" "Jya ku gikorwa kibanza" "Fadhigii hore" "Föregående session" "Kipindi kilichotangulia"
      "முந்தைய அமர்வு" "మునుపటి సెషన్" "เซสชันก่อนหน้า" "Önceki oturum" "Попередня сесія" "Phiên trước" "Seans bi jiitu"
      "Ìgbà iṣẹ́ tó kọjá" "上一个会话" "上一個工作階段" "पिछिला चैट" "Zum vorherigen Chat" "पिछली चैट पर जाएं" "ಹಿಂದಿನ ಚಾಟ್‌ಗೆ ಹೋಗಿ"
      "മുമ്പത്തെ ചാറ്റ്" "Conversa anterior" "Ikiyago kibanziriza" "Ikiganiro kibanziriza" "पिछले टास्क पर जाएं"
      "మునుపటి టాస్క్‌కు వెళ్లండి" "પાછલા સેશન પર જાઓ" "पिछले सेशन पर जाएं" "Sesi sebelumnya" "ಹಿಂದಿನ ಸೆಷನ್‌ಗೆ ಹೋಗಿ"
      "Igihe c’akazi kibanziriza" "Jya ku cyiciro kibanza"
    ) ;;
  back)
    menus=(Go) label='Go › Back' greyed=
    names=(
      "Back" "Zurück" "Atrás" "Retour" "वापस" "Kembali" "Indietro" "戻る" "뒤로" "Voltar" "ወደ ኋላ ይመለሱ" "पीछे" "ফিরে যান"
      "Tilbage" "Takaisin" "Bumalik" "પાછા જાઓ" "Koma baya" "Laghachi azụ" "ಹಿಂದಕ್ಕೆ" "തിരികെ പോകുക" "मागे" "Tilbake"
      "Terug" "Bwererani" "Duubatti deebi'i" "Subira inyuma" "Назад" "Dib u noqo" "Tillbaka" "Rudi" "பின்செல்"
      "వెనక్కి వెళ్లండి" "ย้อนกลับ" "Geri" "Quay lại" "Dellu" "Padà sẹ́yìn" "返回" "Volver" "वापस जाएं" "ಹಿಂದಕ್ಕೆ ಹೋಗಿ"
      "मागे जा"
    ) ;;
  forward)
    menus=(Go) label='Go › Forward' greyed=
    names=(
      "Forward" "Vorwärts" "Adelante" "Suivant" "आगे" "Maju" "Avanti" "進む" "앞으로" "Avançar" "ወደፊት ይሂዱ" "সামনে যান" "Frem"
      "Eteenpäin" "Sumulong" "આગળ જાઓ" "Gaba" "Gaa n’ihu" "ಮುಂದೆ" "മുന്നോട്ട് പോകുക" "पुढे जा" "Fremover" "Vooruit"
      "Pitani patsogolo" "Gara fuulduraa" "Imbere" "Вперёд" "Jya imbere" "Hore u gudub" "Framåt" "Mbele" "முன்னே செல்"
      "ముందుకు వెళ్లండి" "ไปข้างหน้า" "İleri" "Уперед" "Tiến" "Kanam" "Lọ síwájú" "前进" "前進" "आगे जाईं" "Avancer"
      "आगे जाएं" "ಮುಂದಕ್ಕೆ ಹೋಗಿ" "Вперед" "下一頁"
    ) ;;
  terminal)
    menus=(View) label='View › Show Terminal' greyed=$code
    names=(
      "Show Terminal" "Hide Terminal" "Terminal einblenden" "Terminal ausblenden" "Mostrar terminal" "Ocultar terminal"
      "Afficher le terminal" "Masquer le terminal" "टर्मिनल दिखाएं" "टर्मिनल छिपाएं" "Tampilkan Terminal"
      "Sembunyikan Terminal" "Mostra terminale" "Nascondi terminale" "ターミナルを表示" "ターミナルを非表示" "터미널 보기" "터미널 가리기"
      "Mostrar Terminal" "Ocultar Terminal" "ተርሚናል ያሳዩ" "टर्मिनल देखाईं" "টার্মিনাল দেখান" "Vis terminal" "Näytä pääte"
      "Ipakita ang terminal" "ટર્મિનલ બતાવો" "Nuna terminal" "Gosi tamịnalụ" "ಟರ್ಮಿನಲ್ ತೋರಿಸಿ" "ടെർമിനൽ കാണിക്കുക"
      "टर्मिनल दाखवा" "Terminal tonen" "Onetsani terminal" "Tarminaalii agarsiisi" "Erekana terminali"
      "Показать терминал" "Erekana terminal" "Muuji Terminal-ka" "Visa terminal" "Onyesha terminal" "டெர்மினலைக் காட்டு"
      "టెర్మినల్‌ను చూపండి" "แสดงเทอร์มินัล" "Terminali göster" "Показати термінал" "Hiện terminal" "Wone terminal"
      "Fi tẹ́míná hàn" "显示终端" "顯示終端機" "ተርሚናልን ይደብቁ" "टर्मिनल छुपाईं" "টার্মিনাল লুকান" "Skjul terminal" "Piilota pääte"
      "Itago ang terminal" "ટર્મિનલ છુપાવો" "Ɓoye terminal" "Zoo tamịnal" "ಟರ್ಮಿನಲ್ ಮರೆಮಾಡಿ" "ടെർമിനൽ മറയ്ക്കുക"
      "टर्मिनल लपवा" "Terminal verbergen" "Bisani terminal" "Tarminaalii dhoksi" "Hisha terminali" "Скрыть терминал"
      "Hisha terminal" "Qari Terminal-ka" "Dölj terminalen" "Ficha terminal" "டெர்மினலை மறை" "టెర్మినల్‌ను దాచండి"
      "ซ่อนเทอร์มินัล" "Terminali gizle" "Приховати термінал" "Ẩn terminal" "Nëbb terminal bi" "Fi tẽmínà pamọ́" "隐藏终端"
      "隱藏終端機" "Tampilkan terminal" "Toon terminal" "Onyesha skrini ya amri" "Wone terminal bi" "Sembunyikan terminal"
      "터미널 숨기기" "Verberg terminal" "Dölj terminal" "Ficha skrini ya amri" "Fi tẹ́mínà pamọ́"
    ) ;;
  changes)
    menus=(View) label='View › Show Changes' greyed=$code
    names=(
      "Show Changes" "Hide Changes" "Änderungen einblenden" "Änderungen ausblenden" "Mostrar cambios" "Ocultar cambios"
      "Afficher les modifications" "Masquer les modifications" "बदलाव दिखाएं" "बदलाव छिपाएं" "Tampilkan Perubahan"
      "Sembunyikan Perubahan" "Mostra modifiche" "Nascondi modifiche" "変更を表示" "変更を非表示" "변경 사항 보기" "변경 사항 가리기"
      "Mostrar Alterações" "Ocultar Alterações" "ለውጦችን ያሳዩ" "बदलाव देखाईं" "পরিবর্তন দেখান" "Vis ændringer"
      "Näytä muutokset" "Ipakita ang mga pagbabago" "ફેરફારો બતાવો" "Nuna canje-canje" "Gosi mgbanwe"
      "ಬದಲಾವಣೆಗಳನ್ನು ತೋರಿಸಿ" "മാറ്റങ്ങൾ കാണിക്കുക" "बदल दाखवा" "Vis endringer" "Wijzigingen tonen" "Onetsani zosintha"
      "Jijjiiramoota agarsiisi" "Erekana ivyahinduwe" "Показать изменения" "Erekana impinduka" "Muuji isbeddellada"
      "Visa ändringar" "Onyesha mabadiliko" "மாற்றங்களைக் காட்டு" "మార్పులను చూపించండి" "แสดงการเปลี่ยนแปลง"
      "Değişiklikleri göster" "Показати зміни" "Hiện thay đổi" "Wone coppite yi" "Fi àwọn àyípadà hàn" "显示更改" "顯示變更"
      "ለውጦችን ይደብቁ" "बदलाव छिपाईं" "পরিবর্তন লুকান" "Skjul ændringer" "Piilota muutokset" "Itago ang mga pagbabago"
      "ફેરફારો છુપાવો" "Ɓoye canje-canje" "Zoo mgbanwe" "ಬದಲಾವಣೆಗಳನ್ನು ಮರೆಮಾಡಿ" "മാറ്റങ്ങൾ മറയ്ക്കുക" "बदल लपवा"
      "Skjul endringer" "Wijzigingen verbergen" "Bisani zosintha" "Jijjiiramoota dhoksi" "Hisha impinduka"
      "Скрыть изменения" "Qari isbeddellada" "Dölj ändringar" "Ficha mabadiliko" "மாற்றங்களை மறை" "మార్పులను దాచండి"
      "ซ่อนการเปลี่ยนแปลง" "Değişiklikleri gizle" "Сховати зміни" "Ẩn thay đổi" "Nëbb coppite yi"
      "Fi àwọn àyípadà pamọ́" "隐藏更改" "隱藏變更" "পরিবর্তন দেখুন" "Änderungen anzeigen" "Tampilkan perubahan"
      "Toon wijzigingen" "Mostrar alterações" "Hiển thị thay đổi" "Sembunyikan perubahan" "변경 사항 숨기기"
      "Verberg wijzigingen" "Ocultar alterações"
    ) ;;
  files)
    menus=(View) label='View › Show Files' greyed=$code
    names=(
      "Show Files" "Hide Files" "Dateien einblenden" "Dateien ausblenden" "Mostrar archivos" "Ocultar archivos"
      "Afficher les fichiers" "Masquer les fichiers" "फ़ाइलें दिखाएं" "फ़ाइलें छिपाएं" "Tampilkan File"
      "Sembunyikan File" "Mostra file" "Nascondi file" "ファイルを表示" "ファイルを非表示" "파일 보기" "파일 가리기" "Mostrar Arquivos"
      "Ocultar Arquivos" "ፋይሎችን ያሳዩ" "फाइल देखाईं" "ফাইল দেখান" "Vis filer" "Näytä tiedostot" "Ipakita ang mga file"
      "ફાઇલો બતાવો" "Nuna fayiloli" "Gosi faịlụ" "ಫೈಲ್‌ಗಳನ್ನು ತೋರಿಸಿ" "ഫയലുകൾ കാണിക്കുക" "फाइल्स दाखवा"
      "Bestanden tonen" "Onetsani mafayilo" "Faayiloota agarsiisi" "Erekana amadosiye" "Показать файлы" "Erekana dosiye"
      "Muuji faylasha" "Visa filer" "Onyesha faili" "கோப்புகளைக் காட்டு" "ఫైల్‌లను చూపించండి" "แสดงไฟล์"
      "Dosyaları göster" "Показати файли" "Hiển thị tệp" "Wone fiise yi" "Fi àwọn fáìlì hàn" "显示文件" "顯示檔案" "ፋይሎችን ይደብቁ"
      "फाइल छिपाईं" "ফাইল লুকান" "Skjul filer" "Piilota tiedostot" "Itago ang mga file" "ફાઇલો છુપાવો" "Ɓoye fayiloli"
      "Zoo faịlụ" "ಫೈಲ್‌ಗಳನ್ನು ಮರೆಮಾಡಿ" "ഫയലുകൾ മറയ്ക്കുക" "फाइल्स लपवा" "Bestanden verbergen" "Bisani mafayilo"
      "Faayilota dhoksi" "Hisha amadosiye" "Скрыть файлы" "Hisha dosiye" "Qari faylasha" "Dölj filer" "Ficha faili"
      "கோப்புகளை மறை" "ఫైల్‌లను దాచండి" "ซ่อนไฟล์" "Dosyaları gizle" "Сховати файли" "Ẩn tệp" "Nëbb fiise yi"
      "Fi àwọn fáìlì pamọ́" "隐藏文件" "隱藏檔案" "फाइल्स देखाईं" "Toon bestanden" "Mostrar arquivos" "फाइल्स छिपाईं"
      "Sembunyikan file" "파일 숨기기" "Verberg bestanden" "Faayiloota dhoksi" "Ocultar arquivos"
    ) ;;
  preview)
    menus=(View) label='View › Show Browser or Show Preview' greyed=$code
    names=(
      "Show Browser" "Hide Browser" "Show Preview" "Hide Preview" "Browser einblenden" "Browser ausblenden"
      "Vorschau einblenden" "Vorschau ausblenden" "Mostrar navegador" "Ocultar navegador" "Mostrar vista previa"
      "Ocultar vista previa" "Afficher le navigateur" "Masquer le navigateur" "Afficher l'aperçu" "Masquer l'aperçu"
      "ब्राउज़र दिखाएं" "ब्राउज़र छिपाएं" "पूर्वावलोकन दिखाएं" "पूर्वावलोकन छिपाएं" "Tampilkan Browser"
      "Sembunyikan Browser" "Tampilkan Pratinjau" "Sembunyikan Pratinjau" "Mostra browser" "Nascondi browser"
      "Mostra anteprima" "Nascondi anteprima" "ブラウザを表示" "ブラウザを非表示" "プレビューを表示" "プレビューを非表示" "브라우저 보기" "브라우저 가리기" "미리보기 보기"
      "미리보기 가리기" "Mostrar Navegador" "Ocultar Navegador" "Mostrar Pré-visualização" "Ocultar Pré-visualização"
      "አሳሹን ያሳዩ" "ब्राउज़र देखाईं" "ব্রাউজার দেখান" "Vis browser" "Näytä selain" "Ipakita ang browser" "બ્રાઉઝર બતાવો"
      "Nuna burauza" "Gosi ihe nchọgharị" "ಬ್ರೌಸರ್ ತೋರಿಸಿ" "ബ്രൗസർ കാണിക്കുക" "ब्राउझर दाखवा" "Vis nettleser"
      "Browser tonen" "Onetsani msakatuli" "Biraawzarii agarsiisi" "Erekana umushakiro" "Показать браузер"
      "Erekana mushakisha" "Muuji browser-ka" "Visa webbläsare" "Onyesha kivinjari" "உலாவியைக் காட்டு"
      "బ్రౌజర్‌ను చూపండి" "แสดงเบราว์เซอร์" "Tarayıcıyı göster" "Показати браузер" "Hiện trình duyệt"
      "Wone navigateur bi" "Fi aṣàwákiri hàn" "显示浏览器" "顯示瀏覽器" "አሳሽን ይደብቁ" "ब्राउज़र छिपाईं" "ব্রাউজার লুকান"
      "Skjul browser" "Piilota selain" "Itago ang browser" "બ્રાઉઝર છુપાવો" "Ɓoye browser" "Zoo ihe nchọgharị"
      "ಬ್ರೌಸರ್ ಮರೆಮಾಡಿ" "ബ്രൗസർ മറയ്ക്കുക" "ब्राउझर लपवा" "Skjul nettleser" "Browser verbergen" "Bisani msakatuli"
      "Biraawzarii dhoksi" "Hisha umushakisha" "Скрыть браузер" "Hisha mushakisha" "Qari browser-ka" "Dölj webbläsaren"
      "Ficha kivinjari" "உலாவியை மறை" "బ్రౌజర్‌ను దాచండి" "ซ่อนเบราว์เซอร์" "Tarayıcıyı gizle" "Сховати браузер"
      "Ẩn trình duyệt" "Nëbb navigatër bi" "Fi bíráúsà pamọ́" "隐藏浏览器" "隱藏瀏覽器" "ቅድመ-እይታ ያሳዩ" "प्रीव्यू देखाईं"
      "প্রিভিউ দেখান" "Vis forhåndsvisning" "Näytä esikatselu" "Ipakita ang preview" "પૂર્વાવલોકન બતાવો" "Nuna samfoti"
      "Gosi nlele" "ಪೂರ್ವವೀಕ್ಷಣೆ ತೋರಿಸಿ" "പ്രിവ്യൂ കാണിക്കുക" "पूर्वावलोकन दाखवा" "Voorbeeld weergeven"
      "Onetsani chithunzithunzi" "Duraan-argii agarsiisi" "Erekana akarorero" "Показать предпросмотр"
      "Erekana igaragaza mbere" "Muuji horfiirinta" "Visa förhandsgranskning" "Onyesha onyesho la awali"
      "முன்னோட்டத்தைக் காட்டு" "ప్రివ్యూను చూపండి" "แสดงตัวอย่าง" "Önizlemeyi göster" "Показати попередній перегляд"
      "Hiện bản xem trước" "Wone xool-njëkk bi" "Fi àkọ́kọ́wò hàn" "显示预览" "顯示預覽" "ቅድመ-እይታን ይደብቁ" "प्रीव्यू छिपाईं"
      "প্রিভিউ লুকান" "Skjul forhåndsvisning" "Piilota esikatselu" "Itago ang preview" "પૂર્વાવલોકન છુપાવો"
      "Ɓoye samfoti" "Zoo nlele" "ಪೂರ್ವವೀಕ್ಷಣೆ ಮರೆಮಾಡಿ" "പ്രിവ്യൂ മറയ്ക്കുക" "पूर्वावलोकन लपवा" "Voorbeeld verbergen"
      "Bisani chiwonetsero choyambirira" "Duraan-ilaalcha dhoksi" "Hisha irangamwo" "Скрыть предпросмотр"
      "Hisha irebero" "Qari horfiirinta" "Dölj förhandsgranskning" "Ficha onyesho la awali" "முன்னோட்டத்தை மறை"
      "ప్రివ్యూను దాచండి" "ซ่อนตัวอย่าง" "Önizlemeyi gizle" "Сховати попередній перегляд" "Ẩn bản xem trước"
      "Nëbb aperçu bi" "Fi àwòtẹ́lẹ̀ pamọ́" "隐藏预览" "隱藏預覽" "Tampilkan browser" "Toon browser" "Erekana burawuzeri"
      "አሳሹን ይደብቁ" "Ɓoye burauza" "Sembunyikan browser" "브라우저 숨기기" "Verberg browser" "Afficher l’aperçu"
      "Tampilkan pratinjau" "미리보기 표시" "Toon voorbeeld" "Mostrar pré-visualização" "Erekana ingene bizoboneka"
      "Wone xool bu njëkk" "Masquer l’aperçu" "Sembunyikan pratinjau" "미리보기 숨기기" "Verberg voorbeeld" "Durargii dhoksi"
      "Ocultar pré-visualização" "Hisha igaragazambere" "Nëbb apersu bi"
    ) ;;
  palette)
    menus=(View) label='View › Command Palette…' greyed=
    names=(
      "የትዕዛዝ ፓሌት…" "कमांड पैलेट…" "কমান্ড প্যালেট…" "Kommandopalet…" "Befehlspalette…" "Command Palette…"
      "Paleta de comandos…" "Komentopaletti…" "Palette ng command…" "Palette de commandes…" "કમાન્ડ પેલેટ ખોલો…"
      "Jerin umarni…" "Palet perintah…" "Ndepụta iwu…" "Riquadro comandi…" "コマンドパレット…" "ಕಮಾಂಡ್ ಪ್ಯಾಲೆಟ್…" "명령 팔레트…"
      "കമാൻഡ് പാലറ്റ്…" "कमांड पॅलेट…" "Kommandopalett …" "Opdrachtenpalet…" "Mndandanda wa malamulo…"
      "Paaleetii ajajaa…" "Urutonde rw’amategeko…" "Палитра команд…" "Urutonde rw’amabwiriza…" "Command palette-ka…"
      "Kommandopalett…" "Paleti ya amri…" "கட்டளைத் தட்டு…" "కమాండ్ పాలెట్…" "พาเล็ตคำสั่ง…" "Komut paleti…"
      "Палітра команд…" "Bảng lệnh…" "Paletu kumand yi…" "Pẹpẹ àwọn àṣẹ…" "命令面板…" "命令選擇區…"
    ) ;;
  reopen)
    menus=(File) label='File › Reopen Closed Session' greyed="Claude has no closed session to reopen"
    absent="Claude shows it only in its main window, in Claude Code, while no other Claude window has the focus"
    names=(
      "የተዘጋ ክፍለ ጊዜ እንደገና ይክፈቱ" "बंद कइल सेशन फेर से खोलीं" "বন্ধ করা সেশন আবার খুলুন" "Genåbn lukket session"
      "Geschlossene Sitzung wieder öffnen" "Reopen Closed Session" "Reabrir sesión cerrada"
      "Avaa suljettu istunto uudelleen" "Buksan ulit ang isinarang session" "Rouvrir la session fermée"
      "બંધ કરેલ સેશન ફરી ખોલો" "Sake buɗe zaman da aka rufe" "बंद किया गया सेशन फिर से खोलें"
      "Buka kembali sesi yang ditutup" "Mepeghachi nnọkọ e mechiri" "Riapri sessione chiusa" "閉じたセッションを再度開く"
      "ಮುಚ್ಚಿದ ಸೆಷನ್ ಅನ್ನು ಮತ್ತೆ ತೆರೆಯಿರಿ" "닫은 세션 다시 열기" "അടച്ച സെഷൻ വീണ്ടും തുറക്കുക" "बंद केलेले सेशन पुन्हा उघडा"
      "Gjenåpne lukket økt" "Open gesloten sessie opnieuw" "Tsegulaninso seshoni yotsekedwa"
      "Seeshinii cufame irra deebi'ii bani" "Reabrir sessão fechada" "Subira wugurure isesiyo yugawe"
      "Восстановить закрытую сессию" "Ongera ufungure umwanya wafunzwe" "Dib u fur fadhigii la xiray"
      "Öppna stängd session igen" "Fungua upya kipindi kilichofungwa" "மூடிய அமர்வை மீண்டும் திற"
      "మూసివేసిన సెషన్‌ను మళ్లీ తెరవండి" "เปิดเซสชันที่ปิดไปอีกครั้ง" "Kapatılan oturumu yeniden aç"
      "Знову відкрити закриту сесію" "Mở lại phiên đã đóng" "Ubbiwaat sesioŋ bu tëju" "Tún ìgbà iṣẹ́ tí a ti pa dé ṣí"
      "重新打开已关闭的会话" "重新開啟已關閉的工作階段"
    ) ;;
  *) print -u2 -- "Claude: unknown action \"$action\""; exit 1 ;;
esac
# The menu's own name in every language Claude ships.
case $menus in
  Go)
    menus=(
      "Go" "Gehe zu" "Ir" "Aller" "जाएँ" "Buka" "Vai" "移動" "이동" "ሂድ" "जाईं" "যান" "Navigation" "Siirry" "Pumunta" "જાઓ"
      "Je" "Gaa" "ಹೋಗಿ" "പോകുക" "जा" "Gå" "Ga naar" "Pitani" "Deemi" "Genda" "Переход" "Jya" "Tagga" "Nenda" "செல்"
      "వెళ్లండి" "ไป" "Git" "Перехід" "Đi tới" "Dem" "Lọ" "转到" "前往" "ይሂዱ" "जाएं" "Pergi" "Ga" "Tag"
    ) ;;
  View)
    menus=(
      "View" "Ansicht" "Ver" "Affichage" "दृश्य" "Tampilan" "Visualizza" "表示" "보기" "Visualizar" "እይታ" "व्यू" "ভিউ" "Vis"
      "Näytä" "Tingnan" "દૃશ્ય" "Kallo" "Nlele" "ವೀಕ್ಷಣೆ" "കാഴ്ച" "पहा" "Beeld" "Kuwona" "Mul'annoo" "Raba" "Вид"
      "Kureba" "Muuqaalka" "Visa" "Mwonekano" "காட்சி" "వీక్షణ" "มุมมอง" "Görünüm" "Вигляд" "Xem" "Seet" "Ìwò" "视图" "檢視"
      "Igaragaza" "Xool"
    ) ;;
  File)
    menus=(
      "ፋይል" "फाइल" "ফাইল" "Filer" "Datei" "File" "Archivo" "Tiedosto" "Fichier" "ફાઇલ" "Fayil" "फ़ाइल" "Faịlụ" "ファイル"
      "ಫೈಲ್" "파일" "ഫയൽ" "Fil" "Bestand" "Fayilo" "Faayilii" "Arquivo" "Idosiye" "Файл" "Dosiye" "Faylka" "Arkiv" "Faili"
      "கோப்பு" "ఫైల్" "ไฟล์" "Dosya" "Tệp" "Fiise" "Fáìlì" "文件" "檔案"
    ) ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not pgrep by name: an iOS simulator runs its apps under this account too, and Claude for iPhone in one
# would be a "Claude" process as well. lsappinfo asks this login session only — the one whose Claude System Events
# sees — and prints "pid"=<n> for a running app, nothing for one that is not.
[[ $(lsappinfo info -only pid -app com.anthropic.claudefordesktop 2>/dev/null) == *'"pid"='<->* ]] ||
  { print -u2 -- "Claude is not running"; exit 1 }

# Prints nothing, or "!<why not>". The arguments are the label for messages, what to say when the item is greyed out
# (empty: "not available now"), what to say when it is not in the menu (empty: "Claude has no … menu item"), the
# number of menu names, the menu names, then the item names. Only the named menu is searched — never the Window menu,
# whose items are chat titles.
read -r -d '' script <<'OSA'
on itemNamed(theItems, theNames)
	repeat with anItem in theItems
		try
			set itemName to name of anItem
			if itemName is not missing value then
				if theNames contains {itemName} then return contents of anItem
			end if
		end try
	end repeat
	return missing value
end itemNamed

on run argv
	set label to item 1 of argv
	set greyed to item 2 of argv
	set absent to item 3 of argv
	set menuCount to (item 4 of argv) as integer
	set menuNames to items 5 thru (menuCount + 4) of argv
	set theNames to items (menuCount + 5) thru -1 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.anthropic.claudefordesktop")
		if found is {} then return "!Claude is not running"
		tell item 1 of found
			if not frontmost then return "!Claude is not in front"
			set barItem to my itemNamed(menu bar items of menu bar 1, menuNames)
			if barItem is missing value then return "!Claude has no " & (item 1 of menuNames) & " menu in a language this button knows"
			set target to my itemNamed(menu items of menu 1 of barItem, theNames)
			if target is missing value then
				if absent is "" then return "!Claude has no " & label & " menu item"
				return "!" & label & " is not in Claude's menu now: " & absent
			end if
			if not (enabled of target) then
				if greyed is "" then return "!" & label & " is not available in Claude now"
				return "!" & label & " is greyed out: " & greyed
			end if
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$label" "$greyed" "$absent" ${#menus} "${menus[@]}" "${names[@]}" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Claude's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
