-- Translations. Code writes its text in English and passes it through L():
-- on a client in a listed language the translation shows, else the English.
-- A missing translation falls back to the English text, so nothing breaks.
--
--   local L = ns.L
--   Print(L("Debug log off."))
--   Print(string.format(L("Cleared the %s cell of %s."), kind, face))
--
-- Keep format specifiers (%s, %d) in the same order in a translation.
local _, ns = ...

local translations = {}

local function L(text)
    return translations[text] or text
end

local locale = GetLocale and GetLocale() or "enUS"

if locale == "ruRU" then
    translations = {
        -- The game's own functions on the face buttons (tooltips).
        ["Interact"] = "Взаимодействие",
        ["Inspect"] = "Осмотр",
        ["Back"] = "Назад",
        ["Jump"] = "Прыжок",
        ["Target pet"] = "Цель: питомец",
        ["Raid target marker"] = "Метка цели",
        ["Target of target"] = "Цель цели",
        ["Target self"] = "Цель: я",
        ["Shoot"] = "Выстрел",
        ["Assist (target of target)"] = "Помощь (цель цели)",
        ["Target last enemy"] = "Последний враг",
        ["Draw / sheathe weapons"] = "Достать / убрать оружие",
        ["Buffs"] = "Эффекты",
        ["Bags"] = "Сумки",
        ["Target focus"] = "Цель: фокус",
        ["With a living enemy targeted"] = "При выбранном живом враге",
        ["Drop an action here."] = "Перетащите сюда действие.",
    }
end

ns.L = L
ns.locale = locale
