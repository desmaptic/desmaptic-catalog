# Obsidian › Left Sidebar, Right Sidebar, Split Right and Down, Source Mode: an item of Obsidian's View menu, clicked
# through System Events. None of these commands has a default hotkey, so no keystroke reaches them; the menu item runs
# the command itself (Obsidian's main.js: app.commands.executeCommandById), whatever the user's hotkeys and keyboard
# layout. Obsidian names the items in its own language (its Settings, not the Mac's), so the script knows each name in
# every language Obsidian 1.13.7 ships (its i18n files; an untranslated one falls back to English), while the menu
# itself keeps its English name "View" in all of them. The item acts on Obsidian's focused window, so the script refuses
# while Obsidian is not in front, and says so when the item is greyed out (Source Mode in Reading view). It needs
# Accessibility, and the first tap brings up the macOS question about controlling System Events. It never launches
# Obsidian. Every button's command is one line that names the item, then this file (app.json):
#   "action=left-sidebar\n@file:menu/click.zsh"   — left-sidebar, right-sidebar, split-right, split-down, source-mode.
case $action in
  left-sidebar)
    label='View › Left Sidebar'
    names=(
      "Left Sidebar" "የግራ የጎን አሞሌን ቀይር" "تبديل الشريط الجانبي الأيسر" "Згарнуць/разгарнуць левую панэль"
      "বাম সাইডবার চালু/বন্ধ" "Alterna la barra lateral esquerra" "Toggle Left Sidebar" "Venstre sidepanel"
      "Linke Seitenleiste umschalten" "Alternar barra lateral izquierda" "باز/بستن نوار کناری چپ" "Vasen sivupalkki"
      "Basculer la barre latérale gauche" "Taobh na taobh clé" "סרגל צד שמאלי" "Bal oldali oldalsáv ki/be"
      "Peralih Bilah Sisi Kiri" "Mostra/nascondi barra laterale sinistra" "左サイドバーに切り替える" "მარცხენა პანელი"
      "បិទ/បើករបារចំហៀងខាងឆ្វេង" "왼쪽 사이드바 열기/닫기" "Pārslēgt kreiso sānjoslu" "बायाँ साइडबार टगल गर्नुहोस्"
      "Linker zijbalk openen/sluiten" "Lewy pasek boczny" "Alternar Barra Lateral da Esquerda"
      "Alternar para a barra lateral à esquerda" "Свернуть/развернуть левую панель" "Zobraziť/skryť ľavý bočný panel"
      "Пребаци леву бочну траку" "Växla vänster sidofält" "Sol Kenar Çubuğunu Değiştir"
      "Увімкнути/вимкнути ліву бокову панель" "Chap panelni yoqish/o'chirish" "Bật/Tắt Thanh Bên Trái" "折叠/展开左侧边栏"
      "切換左側邊欄"
    ) ;;
  right-sidebar)
    label='View › Right Sidebar'
    names=(
      "Right Sidebar" "የቀኝ የጎን አሞሌ ቀይር" "تبديل الشريط الجانبي الأيمن" "Згарнуць/разгарнуць правую панэль"
      "ডান সাইডবার চালু/বন্ধ" "Alterna la barra lateral dreta" "Toggle Right Sidebar" "Højre sidepanel"
      "Rechte Seitenleiste umschalten" "Alternar barra lateral derecha" "باز/بستن نوار کناری راست" "Oikea sivupalkki"
      "Basculer la barre latérale droite" "Taobh na taobh dheis" "סרגל צד ימני" "Jobb oldali oldalsáv ki/be"
      "Peralih Bilah Sisi Kanan" "Mostra/nascondi barra laterale destra" "右サイドバーに切り替える" "მარჯვენა პანელი"
      "បិទ/បើក របារចំហៀងខាងស្តាំ" "오른쪽 사이드바 열기/닫기" "Pārslēgt labo sānjoslu" "दायाँ साइडबार टगल गर्नुहोस्"
      "Rechter zijbalk openen/sluiten" "Prawy pasek boczny" "Alternar Barra Lateral da Direita"
      "Alternar para a barra lateral à direita" "Свернуть/развернуть правую панель" "Zobraziť/skryť pravý bočný panel"
      "Пребаци десну бочну траку" "Växla höger sidofält" "Sağ Kenar Çubuğunu Değiştir"
      "Увімкнути/вимкнути праву бокову панель" "O'ng panelni yoqish/o'chirish" "Bật/Tắt Thanh Bên Phải" "折叠/展开右侧边栏"
      "切換右側邊欄"
    ) ;;
  split-right)
    label='View › Split Right'
    names=(
      "Split Right" "በቀኝ ተከፈለ" "تقسيم لليمين" "Раздзяліць управа" "ডানে ভাগ করুন" "Divideix cap a la dreta"
      "Rozdělit doprava" "Opdel til højre" "Rechts teilen" "Dividir a la derecha" "نصف کردن به راست"
      "Jaa näkymä oikealle" "Fractionner à droite" "Scoilt ar dheis" "פיצול ימינה" "Felosztás jobbra" "Pisah ke kanan"
      "Dividi a destra" "右に分割" "გაყოფა მარჯვნივ" "បំបែក​ខាង​ស្ដាំ" "오른쪽 분할" "Sadale pa labi" "दायाँ विभाजन"
      "Rechts opdelen" "Del til høyre" "Podziel w prawo" "Dividir à direita" "Dividir para a direita"
      "Împarte la dreapta" "Разделить вправо" "Rozdeliť vpravo" "Ndaj djathtas" "Подели десно" "Dela till höger"
      "แบ่งทางขวา" "Sağa Böl" "Розділити праворуч" "O'ngga bo'lish" "Chia 2 Bên Phải" "左右分屏" "向右分割"
    ) ;;
  split-down)
    label='View › Split Down'
    names=(
      "Split Down" "ወደ ታች ተከፈለ" "تقسيم للأسفل" "Раздзяліць уніз" "নিচে ভাগ করুন" "Divideix cap avall" "Rozdělit dolů"
      "Opdel nedad" "Unten teilen" "Dividir abajo" "نصف کردن به پایین" "Jaa näkymä alas" "Fractionner en bas"
      "Roinn síos" "פיצול למטה" "Felosztás lefelé" "Pisah ke bawah" "Dividi sotto" "下に分割" "გაყოფა ქვემოთ" "បំបែកចុះ"
      "아래쪽 분할" "Sadale uz leju" "स्प्लिट डाउन" "Beneden opdelen" "Del nedover" "Podziel w dół" "Dividir para baixo"
      "Împarte în jos" "Разделить вниз" "Rozdeliť dole" "Ndaj poshtë" "Подели доле" "Dela nedåt" "แบ่งลงล่าง"
      "Aşağı Böl" "Розділити знизу" "Pastga bo'lish" "Chia 2 Xuống Dưới" "上下分屏" "向下分割"
    ) ;;
  source-mode)
    label='View › Source Mode'
    names=(
      "Source Mode" "የምንጭ ሁነታ" "وضع المصدر" "Зыходны код" "সোর্স মোড" "Mode font" "Režim zdroje" "Kildetilstand"
      "Quellcode-Ansicht" "Modo fuente" "حالت منبع" "Lähdekooditila" "Mode source" "Mód Foinse" "מצב מקור" "Forrásmód"
      "Mode Sumber" "Codice sorgente" "ソースモード" "წყაროს რეჟიმი" "ម៉ូដប្រភព" "원본 모드" "Avota režīms" "Mod sumber"
      "स्रोत मोड" "Bronweergave" "kildemodus" "Tryb źródłowy" "Modo Origem" "Modo de Origem" "Mod sursă"
      "Просмотр исходного кода" "Režim zdrojového kódu" "Modaliteti i burimit" "Режим извора" "Källkodsläge"
      "โหมดซอร์ส" "Kaynak Modu" "Джерельний режим" "Manba kodini ko'rish" "Chế Độ Nguồn" "源码模式" "原始碼模式"
    ) ;;

  *) print -u2 -- "Obsidian: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Obsidian System Events sees.
pgrep -xqU $UID Obsidian || { print -u2 -- "Obsidian is not running"; exit 1 }

# Prints nothing, or "!<why not>". The item is looked for in the View menu first, then in the other menus, should an
# Obsidian version move it or name its menus in its own language.
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
	set theNames to rest of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "md.obsidian")
		if found is {} then return "!Obsidian is not running"
		tell item 1 of found
			if not frontmost then return "!Obsidian is not in front"
			set target to missing value
			if exists menu bar item "View" of menu bar 1 then
				set target to my itemNamed(menu items of menu 1 of menu bar item "View" of menu bar 1, theNames)
			end if
			if target is missing value then
				repeat with barItem in (menu bar items of menu bar 1)
					try
						set target to my itemNamed(menu items of menu 1 of barItem, theNames)
					end try
					if target is not missing value then exit repeat
				end repeat
			end if
			if target is missing value then return "!Obsidian has no " & label & " menu item"
			if not (enabled of target) then return "!" & label & " is not available in Obsidian now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$label" "${names[@]}" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Obsidian's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
