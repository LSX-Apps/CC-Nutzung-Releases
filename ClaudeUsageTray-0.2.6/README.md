# Claude Usage Tray fuer Windows

Diese kleine App zeigt unten rechts in Windows an, wie viel Claude-Pro/Max-
Nutzung schon verbraucht ist.

Das Tray-Icon zeigt eine Ampel:

- Gruen mit Haken: alles okay
- Orange mit Ausrufezeichen: ab 70 Prozent
- Rot mit Ausrufezeichen: ab 90 Prozent

Die genauen Werte stehen im Rechtsklick-Menue des Icons.

## Installation fuer normale Nutzer

1. ZIP entpacken.
2. `ClaudeUsageTray-Setup.cmd` doppelklicken.
3. Im Assistenten Schritt fuer Schritt durchgehen:
   - Claude Code installieren
   - Login starten
   - Tray installieren

Nach der Installation ist das Icon unten rechts in der Windows-Taskleiste.
Manchmal steckt es zuerst im kleinen Pfeil-Menue.

## Was ist Claude Code und warum braucht die App das?

Claude selbst laeuft normalerweise im Browser oder in der Desktop-App. Die
Nutzungsdaten, die diese Tray-App braucht, sind aber nicht als normale
oeffentliche API verfuegbar.

Claude Code ist das Terminal-Programm von Anthropic. Wenn man sich dort einmal
anmeldet, legt es lokal eine Login-Datei an. Diese App nutzt diese lokale
Login-Datei, um die Usage-Werte abzufragen.

Claude Code muss danach nicht dauerhaft offen bleiben.

## Manuelle Installation ohne Assistent

```powershell
powershell -ExecutionPolicy Bypass -File .\install-ccusage-windows.ps1
```

## Test

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ClaudeUsageTray\ccusage-poll.ps1" -VerboseOutput
```

Die Ausgabe-Datei liegt hier:

```text
%USERPROFILE%\.claude\cc-usage.json
```

## Deinstallation

```powershell
powershell -ExecutionPolicy Bypass -File .\install-ccusage-windows.ps1 -Uninstall
```

## Updates

Im Tray-Menü gibt es **Update prüfen**. 

Das ist standardmäßig so vorkonfiguriert, dass die App im öffentlichen GitHub-Repository `LSX-Apps/CC-Nutzung-Releases` nach neuen Releases sucht. Du musst also nichts weiter einstellen.

Für das Erstellen und Veröffentlichen neuer Releases siehe [RELEASE-HOWTO.md](RELEASE-HOWTO.md).

