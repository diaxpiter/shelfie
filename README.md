# Shelfie

A cheerful reading-dashboard home screen for [KOReader](https://github.com/koreader/koreader), designed for black-and-white e-ink.

> **Status: early work in progress (v0.2.2).** Tested in the desktop emulator; device testing in progress. Expect rough edges.

```
┌──────────────────────────────────────┐
│ Wed, 11 Nov              11:32 · 87% │
│ ╭──────────────────────────────────╮ │
│ │ ▓▓▓  KEEP READING           ╭──╮ │ │
│ │ ▓▓▓  Torto Arado            │61%│ │ │
│ │ ▓▓▓  Page 142 of 233 · 38m  ╰──╯ │ │
│ │      ( Continue → )              │ │
│ ╰──────────────────────────────────╯ │
│ ╭────────╮ ╭────────╮ ╭────────╮     │
│ │ 12     │ │ 34/45m │ │ 9      │     │
│ │ streak │ │ ▓▓▓▓░  │ │ books  │     │
│ ╰────────╯ ╰────────╯ ╰────────╯     │
│ Recently added              See all  │
│ ▢ ▢ ▢ ▢                              │
│                                      │
│ [Home] Library  Stats  Tags  Settings│
└──────────────────────────────────────┘
```

## Features

- **Keep reading card**: the book you're in the middle of, with its cover, page, estimated time left, a *Continue* button and a progress ring.
- **Stats tiles**: your reading streak, today's minutes against a daily goal (tap to change it) and books finished this year. The numbers come from KOReader's built-in *Reading statistics* plugin.
- **Recently added**: the four newest books in your home folder. Covers come from KOReader's cover browser cache, and books without a cover get a patterned placeholder.
- **Library**: every book as a cover grid with title and progress. Filter by All / Reading / New / Finished, swipe or use the arrows to change pages, tap to read, long-press for book info. *Folders* opens KOReader's own file browser.
- **Stats**: streak, this week, this month, a 7-day chart against your daily goal, and all-time numbers. *Calendar* opens KOReader's detailed view.
- **Tags**: your collections as cards. Tap one to browse it in the library grid; *Manage* creates or renames collections.
- **Settings**: daily goal, start-up behaviour, dictionaries, frontlight, Wi-Fi, and shortcuts to KOReader's full menu.
- **Hiding**: dictionary files (e.g. Amazon *Dicionário…*, anything in a `dictionaries` folder) are hidden automatically; long-press any cover → *Hide from Shelfie* for others. Bring them back in Settings.
- **Tab bar** on every page: Home · Library · Stats · Tags · Settings.

Shelfie only reads your data. It never changes books, history or statistics.

## Install

1. Download the latest release and unzip it.
2. Copy the `shelfie.koplugin` folder into `koreader/plugins/` on your device.
3. Restart KOReader. Shelfie appears whenever the library opens.

Settings are under **Tools → Shelfie**: open the home screen, turn showing it on library open on or off, and set the daily goal.

Tip: the *Reading statistics* and *Cover browser* plugins should be enabled (they are by default).

## Compatibility

Developed and tested against KOReader **v2026.07.1**. Not meant to be used together with other home-screen replacements (SimpleUI, ZenOS, Project: Title), since they take over the same screen.

## Development

Run it on a desktop KOReader (Linux build) by linking the repo into its `plugins/` folder:

```sh
ln -s "$PWD" /path/to/koreader/plugins/shelfie.koplugin
EMULATE_READER_W=1072 EMULATE_READER_H=1448 EMULATE_READER_DPI=300 /path/to/koreader/bin/koreader
```

Set `SHELFIE_DEV_SHOT=/tmp/shot.png` to save a screenshot of the home screen and quit. This is useful for checking layout changes.

## License

[AGPL-3.0](LICENSE), the same license as KOReader.
