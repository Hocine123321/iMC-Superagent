# Preparing the game files on your PC (Linux) and copying them to the iPhone

Everything below runs on your PC. Nothing is installed on the phone except the Horizon app.
Your game files stay on your own devices.

## 1. Let the Horizon launcher prepare version 26.3

1. Open the **official Horizon launcher** on the PC.
2. Pick the **26.3** build and press **Play** once. It prepares the files from your own Minecraft
   install, copies the sounds, then starts the desktop game. You can close the game as soon as it
   reaches the title screen.
3. If it asks for Java 25, let it download it.

## 2. Find the prepared folder

On Linux it is here (the `<tag>` is the Horizon build you pressed Play on):

```
~/.local/share/horizon-launcher/versions/<tag>/.local/horizon-client/26.3/
```

Find it with:

```
ls -d ~/.local/share/horizon-launcher/versions/*/.local/horizon-client/26.3
```

If you moved the launcher's data folder (Settings > Data folder), look under that location instead.
(Source: `launcher/src/backend.rs`, the resources path is `<version folder>/.local/horizon-client/<game version>`.)

## 3. Check it is complete before copying

```
D=~/.local/share/horizon-launcher/versions/<tag>/.local/horizon-client/26.3
ls "$D/horizon-resources.json"        # must exist: the app refuses the folder without it
du -sh "$D"                           # expect roughly 500 MB
du -sh "$D"/sounds 2>/dev/null        # expect roughly 380 MB; much smaller means a silent game
```

Do not copy a folder that is missing `horizon-resources.json`.

## 4. Copy it to the iPhone

The Horizon app creates a folder visible in the Files app. Open the app **once** first.

1. Connect the phone, or use AirDrop alternatives (a USB cable, a cloud drive, or a local share).
2. On the phone open **Files > On My iPhone > Horizon > Horizon** (the same folder where you found
   `diagnostics.txt`). It already holds an empty `resources` folder and a `home` folder.
3. Fill `resources` so that this file exists:

```
On My iPhone/Horizon/Horizon/resources/horizon-resources.json
```

Copy the **contents** of `26.3/` into `resources/`, not the `26.3` folder itself.
Copying about 500 MB over the Files app is slow; a cable and a computer file manager is faster.

## 5. Start the app

Open Horizon. If the files are found it goes past the "prepared game files are missing" screen.
If it still shows that screen, send me the path you used and the output of `ls` for that folder.

## Things to know

- The prepared folder is derived from your copy of the game. Keep it private and do not share it.
- Which of these files the engine reads at run time is not measured yet (milestone M3). The full
  folder is the safe choice for now.
