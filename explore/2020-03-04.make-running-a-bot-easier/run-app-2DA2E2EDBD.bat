@echo off
@echo This is a script to run the app found at https://botcatalog.org/bot/2DA2E2EDBDCE6D2824C76A6FB48064B11CC6A742667F607148C5C9A63ED14AE1 ...
@echo.
@echo Below is the beginning of the app description found on the catalog:
@echo.
@echo {- Michaels EVE Online mining bot version 2020-02-13
@echo The bot warps to an asteroid belt, mines there until the ore hold is full, and then docks at a station to unload the ore. It then repeats this cycle until you stop it.
@echo [...]
@echo.

where botengine.exe >nul 2>nul
if %ErrorLevel% equ 0 (
    botengine.exe  run-bot  https://github.com/Viir/bots/tree/4a8c9b900f8676c2bb98d2f3c9e91cd945439234/implement/applications/eve-online/eve-online-mining-bot
) else (
    @echo I failed to run the app because I did not find the 'botengine.exe' program.
    @echo.
    @echo Please see https://to.botengine.org/failed-run-bot-did-not-find-botengine-program for a guide on how to install the 'botengine.exe' program so that I can find it.
    @start "" https://to.botengine.org/failed-run-bot-did-not-find-botengine-program
)

pause
