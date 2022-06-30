# MiSTer Favorites

Add and manage favorites in your [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki) menu.

![GUI](https://github.com/wizzomafizzo/MiSTer_Favorites/raw/main/images/gui.png)

This script works well with the [Games Menu](https://github.com/wizzomafizzo/MiSTer_GamesMenu) and [BGM](https://github.com/wizzomafizzo/MiSTer_BGM) scripts.

## Features

* Link shortcuts for system cores, arcade cores and games to your main MiSTer menu or a dedicated favorites folder.
* Automatically generates .mgl files to launch games directly from the menu.
* Supports selecting games from inside .zip files.
* Automatically fixes broken shortcuts when a core has been updated.
* Edit and remove existing favorite entries from the GUI.
* Works without a keyboard.

## Installation

1. Copy the [favorites.sh](https://github.com/wizzomafizzo/MiSTer_Favorites/raw/main/favorites.sh) file to your SD card's `Scripts` folder.
2. Run `favorites` from the Scripts menu.

### Updates

Favorites can be automatically updated with the MiSTer downloader script (and update_all). Add the following text to the `downloader.ini` file on your SD card:

```
[favorites]
db_url = 'https://raw.githubusercontent.com/wizzomafizzo/MiSTer_Favorites/main/favorites.json'
```

## Usage

Launch `favorites` from the Scripts menu and follow the prompts.

## FAQ

* *Why can't I add games for a certain system?*

  Support for direct game links depend on a core's own support for .mgl files. Submit a feature request with the core's author if you want support added. Report an issue here if you know the core already has .mgl support, and it can be added to work with this script.

* *Can I add subfolders to the @Favorites menu?*

  Yes, but you have to set them up yourself. Create any number or depth of folders yourself in the @Favorites folder and the script will automatically pick up on them when it's time to select where a favorite will go. Make sure every folder you create has a `_` in front of the name, or else the MiSTer menu won't see it. There are currently no plans to add support for managing subfolders from the Favorites GUI.