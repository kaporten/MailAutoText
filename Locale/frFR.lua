local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("MailAutoText", "frFR")
if not L then return end

L["Subject_Items"] = "Envoi d'éléments"
L["Subject_Cash"] = "Envoyer de l'argent"
L["Subject_Both"] = "Envoi des articles et de l'argent"
L["Subject_COD"] = "Envoi d'éléments de paiement"

L["MatchedSource_Tooltip_Alt"] = "Alt"
L["MatchedSource_Tooltip_Friend"] = "Voisin"
L["MatchedSource_Tooltip_Guild"] = "Membre de la guilde" 
L["MatchedSource_Tooltip_Circle"] = "Membre du cercle '%s'"