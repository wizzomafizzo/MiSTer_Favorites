# MiSTer Favorites (archived)

Development moved to the main [mrext repository](https://github.com/wizzomafizzo/mrext#favorites).

Current source and manual download: [`scripts/favorites.sh`](https://github.com/wizzomafizzo/mrext/raw/main/scripts/favorites.sh)

## Existing MiSTer Downloader installations

The standalone Favorites downloader database will no longer receive updates from this repository. Downloader configuration is not migrated automatically.

In `downloader.ini` on the SD card, remove the old Favorites entry:

```ini
[favorites]
db_url = https://raw.githubusercontent.com/wizzomafizzo/MiSTer_Favorites/main/favorites.json
```

Replace it with the combined mrext database:

```ini
[mrext/all]
db_url = https://raw.githubusercontent.com/wizzomafizzo/mrext/main/releases/all.json
```

Then run `downloader` or `update` from the MiSTer Scripts menu.

This repository remains available as a read-only archive. Its complete Git history and contributor authorship were imported into `wizzomafizzo/mrext` before archival.
