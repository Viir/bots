
@echo off
@echo This is a script to run the app found at https://botcatalog.org/bot/0EA84324F370A3936A9437939A053504053DAECDD3AC04AB6D5F6DDEDEC1EABF
@echo.
@echo Below is the beginning of the app description found on the catalog:
@echo.
@echo {- Tribal Wars 2 farmbot version 2020-02-26
@echo I search for barbarian villages around your villages and then attack them.
@echo.
@echo [...]
@echo.

where botengine.exe >nul 2>nul
if %ErrorLevel% equ 0 (
    botengine.exe  run-bot  https://github.com/Viir/bots/tree/44033f2e4115d3253b39781fcc8e002f6538a1a1/implement/applications/tribal-wars-2/tribal-wars-2-farmbot
) else (
    @echo I failed to run the app because I did not find the 'botengine.exe' program.
    @echo.
    @echo Please see https://to.botengine.org/failed-run-bot-did-not-find-botengine-program for a guide on how to install the 'botengine.exe' program so that I can find it.
    @start "" https://to.botengine.org/failed-run-bot-did-not-find-botengine-program
)

pause
