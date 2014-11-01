-- Default english localization
local debug = false
local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("MailAutoText", "enUS", true, not debug)

if not L then
	return
end

L["Subject_Items"] = "Sending items"
L["Subject_Cash"] = "Sending cash"
L["Subject_Both"] = "Sending cash and items"
L["Subject_COD"] = "Sending items for payment"

L["MatchedSource_Tooltip_Alt"] = "Alt"
L["MatchedSource_Tooltip_Friend"] = "Friend"
L["MatchedSource_Tooltip_Guild"] = "Guild member" 
L["MatchedSource_Tooltip_Circle"] = "Member of circle '%s'"