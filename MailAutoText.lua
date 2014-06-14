require "Window"
require "GameLib"
require "Apollo"
 
--local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("MailAutoText", false, {})

local MailAutoText = {}

function MailAutoText:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

function MailAutoText:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {}
	
	Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end

function MailAutoText:OnLoad()
	-- TODO: Check if "Mail" is installed (or have been replaced)
	--Apollo.GetAddon("Mail").luaComposeMail:FindChild("HeaderTitle"):SetText("Nyt og moderne!")
	Apollo.RegisterEventHandler("MailAddAttachment", "OnMailAddAttachment", self)
end

function MailAutoText:OnMailAddAttachment()
	Print("Yarr!")
	Apollo.GetAddon("Mail")
end


local MailAutoTextInst = MailAutoText:new()
MailAutoTextInst:Init()
