# Preparing the game files on Linux, Windows, or macOS

Prepare the files on a computer with the Horizon Launcher, then import them into iMC Horizon on your iPhone. You need your own copy of Minecraft: Java Edition; the app does not include Minecraft files. Keep the prepared folder private.

## 1. Prepare the files

1. Open the **Horizon Launcher** on your computer.
2. Select the **26.3** build and press **Play** once. The launcher prepares the files from your Minecraft installation, including the sounds, and then starts the desktop game. You can close the game when it reaches the title screen.
3. If the launcher asks for Java 25, let it download and install it.

## 2. Find the prepared folder

The default location depends on your computer. Replace `<tag>` with the name of the Horizon build folder you launched. The prepared files are inside that folder at `.local/horizon-client/26.3/`.

| Computer | Prepared folder |
|---|---|
| Linux | `~/.local/share/horizon-launcher/versions/<tag>/.local/horizon-client/26.3/` |
| macOS | `~/Library/Application Support/horizon-launcher/versions/<tag>/.local/horizon-client/26.3/` |
| Windows | `%APPDATA%\horizon-launcher\versions\<tag>\.local\horizon-client\26.3\` |

On Windows, `%APPDATA%` normally expands to `C:\Users\<you>\AppData\Roaming`. You can paste `%APPDATA%\horizon-launcher\versions` into File Explorer's address bar, open the folder for the build you launched, then follow `.local\horizon-client\26.3`.

On macOS, in Finder press **Command-Shift-G** and enter `~/Library/Application Support/horizon-launcher/versions`; then open the folder for the build you launched and follow `.local/horizon-client/26.3`.

On Linux, list the prepared folders with:

```sh
ls -d ~/.local/share/horizon-launcher/versions/*/.local/horizon-client/26.3
```

If you changed **Settings > Data folder** in the Horizon Launcher, use that selected data folder instead of the default OS location above. Under it, look for `versions/<tag>/.local/horizon-client/26.3/`.

## 3. Check that preparation completed

In your file manager, compress the prepared **`26.3` folder** into a ZIP archive. Check the ZIP's size: it should be **over 500 MB**. That is the quick check that the prepared game files are all there. Keep the original `26.3` folder; that is the folder iMC Horizon imports.

## 4. Transfer and import on the iPhone (recommended)

Copy the whole prepared `26.3` folder to a place the iPhone's Files app can access. For example, use iCloud Drive, AirDrop from a Mac, or a cloud-storage app whose files appear in Files. On Windows, iCloud Drive or another Files-compatible cloud provider works; on Linux, use a transfer or storage method available on your iPhone. A USB connection by itself may not make the computer's folders available in Files. If you transfer the ZIP instead, extract it in Files first; the app imports a folder, not a ZIP file.

1. Open iMC Horizon on the iPhone.
2. Go to **Game files > Import a folder**.
3. In the Files picker, select the prepared `26.3` folder (the one containing `horizon-resources.json`). The app copies and checks the files before using them.
4. When the import finishes, use **Game files > Check** if you want to run the check again, then return to Play.

The app's files are also visible in Files under **On My iPhone > iMC Horizon > Horizon**. Its game resources live in the `resources` folder.

## 5. Optional: copy the contents manually

Open iMC Horizon once so its folder is created, then use a file-transfer method that can access the app's Files documents. Copy the **contents** of the prepared `26.3` folder into:

```text
On My iPhone/iMC Horizon/Horizon/resources/
```

Copy the contents, not the `26.3` folder itself. The resulting `resources` folder must contain `horizon-resources.json`. The app's **Game files > Check** button verifies the folder.

## Things to know

- The prepared folder is derived from your own game installation. Keep it private and do not share it.
- The full folder is the safe choice for now; exactly which files the engine reads at runtime has not yet been measured (milestone M3).
