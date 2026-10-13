# Notion › Back (tap), Forward (long press) and Sidebar: History › Back or Forward and View › Show/Hide Sidebar in
# Notion's menu, clicked through System Events. Their shortcuts, ⌘[, ⌘] and ⌘\, sit on keys that German, French,
# Spanish, Nordic, Swiss and other layouts type only with Option or Shift, so the keystroke misses there; the menu item
# runs the same command (app.asar: goBack, goForward, toggleSidebarInNotion of the focused window) on every layout.
# Notion names its menus in its own language (its setting, not the Mac's), so the script knows the names in every
# language Notion 7.35.1 ships (its i18n/<lang>/messages.json; a language it does not ship shows English). Only the
# named menu is searched — never the Window menu, whose items are page titles. The item acts on Notion's focused
# window, so the script refuses while Notion is not in front. It needs Accessibility, and the first tap brings up the
# macOS question about controlling System Events. It never launches Notion. Every button's command is one line that
# names the item, then this file (app.json):
#   "action=back\n@file:menu/click.zsh"   — back, forward or sidebar.
case $action in
  back)
    menu=history label='History › Back'
    names=(
      "Back" "Zurück" "Atrás" "Précédent" "Indietro" "Voltar" "Terug" "Tilbage" "Tillbaka" "Tilbake" "Takaisin" "戻る"
      "뒤로" "返回" "ย้อนกลับ" "Quay lại" "Kembali" "חזרה" "رجوع"
    ) ;;
  forward)
    menu=history label='History › Forward'
    names=(
      "Forward" "Weiter" "Adelante" "Suivant" "Avanti" "Avançar" "Volgende" "Fremad" "Nästa" "Framover" "Eteenpäin"
      "進む" "앞으로" "前进" "前進" "ไปข้างหน้า" "Chuyển tiếp" "Teruskan" "הבא" "إعادة توجيه"
    ) ;;
  sidebar)
    menu=view label='View › Show/Hide Sidebar'
    names=(
      "Show/Hide Sidebar" "Show/hide sidebar" "Seitenleiste ein-/ausblenden" "Mostrar/ocultar barra lateral"
      "Mostrar/Ocultar la barra lateral" "Afficher/masquer la barre latérale" "Mostra/Nascondi la barra laterale"
      "Zijbalk weergeven/verbergen" "Vis/skjul sidemenu" "Visa/dölj sidofält" "Vis/skjul sidestolpe"
      "Näytä/piilota sivuvalikko" "サイドバーの表示/非表示" "사이드바 표시/숨기기" "显示/隐藏侧边栏" "顯示/隱藏側邊欄"
      "แสดง/ซ่อนแถบด้านข้าง" "Hiện/Ẩn thanh bên" "Tampilkan/Sembunyikan Bilah Sisi" "הצגה/הסתרה של סרגל הצד"
      "إظهار/إخفاء الشريط الجانبي"
    ) ;;
  *) print -u2 -- "Notion: unknown action \"$action\""; exit 1 ;;
esac
# The menu's own name in every language Notion ships.
case $menu in
  history)
    menus=(
      "History" "Verlauf" "Historial" "Historique" "Cronologia" "Histórico" "Geschiedenis" "Historik" "Historikk"
      "Historia" "履歴" "기록" "历史" "歷史" "ประวัติ" "Lịch sử" "Riwayat" "היסטוריה" "التاريخ"
    ) ;;
  view)
    menus=(
      "View" "Ansicht" "Ver" "Afficher" "Visualizza" "Visualizar" "Weergeven" "Visning" "Visa" "Vis" "Näkymä" "表示"
      "보기" "视图" "瀏覽模式" "ดู" "Chế độ xem" "Lihat" "תצוגה" "عرض"
    ) ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not by process name: a web app saved from Safari as "Notion" is a "Notion" process too.
[[ -n $(lsappinfo info -only pid -app notion.id 2>/dev/null) ]] || { print -u2 -- "Notion is not running"; exit 1 }

# Prints nothing, or "!<why not>". The arguments are the item's and the menu's English names for messages, the number of
# menu names, the menu names, then the item names.
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
	set menuLabel to item 2 of argv
	set menuCount to (item 3 of argv) as integer
	set menuNames to items 4 thru (menuCount + 3) of argv
	set itemNames to items (menuCount + 4) thru -1 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "notion.id")
		if found is {} then return "!Notion is not running"
		tell item 1 of found
			if not frontmost then return "!Notion is not in front"
			set barItem to my itemNamed(menu bar items of menu bar 1, menuNames)
			if barItem is missing value then return "!Notion has no " & menuLabel & " menu in a language this button knows"
			set target to my itemNamed(menu items of menu 1 of barItem, itemNames)
			if target is missing value then return "!Notion has no " & label & " menu item"
			if not (enabled of target) then return "!" & label & " is not available in Notion now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$label" "${label%% ›*}" ${#menus} "${menus[@]}" "${names[@]}" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Notion's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
