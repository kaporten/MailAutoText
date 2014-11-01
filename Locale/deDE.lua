local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("MailAutoText", "deDE")
if not L then return end

L["Subject_Items"] = "Gegenstände senden"
L["Subject_Cash"] = "Geld senden"
L["Subject_Both"] = "Geld und Gegenstände senden"
L["Subject_COD"] = "Geld anfragen"

L["MatchedSource_Tooltip_Alt"] = "Alt"
L["MatchedSource_Tooltip_Friend"] = "Kontakte"
L["MatchedSource_Tooltip_Guild"] = "Gildenmitglied" 
L["MatchedSource_Tooltip_Circle"] = "Mitglied der Zirkel '%s'"