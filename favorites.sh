#!/usr/bin/env python

import os
import subprocess
import sys
import glob
import re

SD_ROOT = "/media/fat"
FAVORITES_DB = os.path.join(SD_ROOT, "favorites.txt")
FAVORITES_NAME = "_@Favorites"
FAVORITES_FOLDER = os.path.join(SD_ROOT, FAVORITES_NAME)
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"

ALLOWED_FILES = [".rbf", ".mra"]

# by default hide all the unnecessary files in the SD root
HIDE_SD_FILES = True
ALLOWED_SD_FILES = ["_Arcade", "_Console", "_Computer", "_Other", "_Utility", "games"]

WINDOW_TITLE = "Favorites Manager"
WINDOW_DIMENSIONS = ["20", "75", "20"]


# read favorites file and return list of [target core -> link location]
def read_config():
    if os.path.exists(FAVORITES_DB):
        favorites = []
        with open(FAVORITES_DB, "r") as f:
            for line in f.readlines():
                entry = line.split("\t")
                if len(entry) == 2:
                    favorites.append([entry[0], entry[1].rstrip()])
        return favorites
    else:
        return []


# write list of [target core -> link location] to favorites file
def write_config(favorites):
    with open(FAVORITES_DB, "w") as f:
        for entry in favorites:
            f.write("{}\t{}\n".format(entry[0], entry[1]))


def create_link(entry):
    os.symlink(entry[0], entry[1])


def delete_link(entry):
    os.remove(entry[1])


# check if symlink goes to an existing file
def link_valid(entry):
    if os.path.islink(entry[1]):
        path = os.readlink(entry[1])
    else:
        return False


def add_favorite(core_path, favorite_path):
    config = read_config()
    entry = [core_path, favorite_path]
    create_link(entry)
    config.append(entry)
    write_config(config)


# remove favourite at on n line in favorites file
def remove_favorite(index):
    # TODO: remove based on contents instead of index?
    config = read_config()
    if len(config) == 0 or len(config) < index:
        return
    entry = config.pop(index)
    delete_link(entry)
    write_config(config)


def make_mgl(rbf, delay, type, index, path):
    mgl = "<mistergamedescription>\n\t<rbf>{}</rbf>\n\t<file delay=\"{}\" type=\"{}\" index=\"{}\" path=\"{}\"/>\n</mistergamedescription>"
    return mgl.format(rbf, delay, type, index, path)


def create_favorites_folder():
    if not os.path.exists(FAVORITES_FOLDER):
        os.mkdir(FAVORITES_FOLDER)


# delete any create folder and symlinks that aren't required anymore
def cleanup_favorites():
    # TODO: delete the root cores symlink if it's safe
    if os.path.exists(FAVORITES_FOLDER):
        files = os.listdir(FAVORITES_FOLDER)
        if len(files) == 0:
            os.rmdir(FAVORITES_FOLDER)
        elif len(files) == 1 and files[0] == "cores":
            # clean up arcade cores symlink
            os.remove(os.path.join(FAVORITES_FOLDER, "cores"))
            os.rmdir(FAVORITES_FOLDER)


def get_menu_output(output):
    try:
        return int(output)
    except ValueError:
        return None


def display_main_menu():
    config = read_config()

    def menu():
        args = [
            "dialog", "--title", WINDOW_TITLE, 
            "--ok-label", "Select", "--cancel-label", "Exit",
            "--menu", "Add a new favorite or select an existing one to delete.",
            WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1], WINDOW_DIMENSIONS[2],
            "1", "<ADD NEW FAVORITE>",
            "",  "------------------"
        ]

        number = 2
        for entry in config:
            args.append(str(number))
            args.append(str(entry[1].replace(SD_ROOT, "")))
            number += 1

        result = subprocess.run(args, stderr=subprocess.PIPE)

        selection = get_menu_output(result.stderr.decode())
        button = get_menu_output(result.returncode)

        return selection, button

    selection, button = menu()
    # ignore separator menu items
    while selection == None and button == 0:
        selection, button = menu()
    
    if button == 0:
        if selection == 1:
            return "__ADD__"
        else:
            return config[selection - 2][1]
    else:
        return None


def display_add_favorite_name(item):
    args = [
        "dialog", "--title", WINDOW_TITLE, "--inputbox",
        "Enter a display name for the favorite. Dates and names.txt replacements will still apply.",
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1]
    ]

    orig_name, ext = os.path.splitext(os.path.basename(item))
    args.append(orig_name)

    result = subprocess.run(args, stderr=subprocess.PIPE)

    name = str(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        return name + ext
    else:
        return None


def display_add_favorite_folder():
    # TODO: show subfolders in favorites folder
    args = [
        "dialog", "--title", WINDOW_TITLE, "--ok-label", "Select",
        "--menu", "Select a folder to place favorite.",
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1], WINDOW_DIMENSIONS[2],
        "1", "<TOP LEVEL>",
        "2", "{}/".format(FAVORITES_NAME)
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        if selection == 1:
            return "__ROOT__"
        else:
            return "_@Favorites"
    else:
        return None


def display_delete_favorite(path):
    args = [
        "dialog", "--title", WINDOW_TITLE, "--yesno",
        "Delete favorite {}?".format(path.replace(SD_ROOT, "")),
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1]
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE)

    button = get_menu_output(result.returncode)

    if button == 0:
        config = read_config()
        index = 0
        for entry in config:
            if path == entry[1]:
                remove_favorite(index)
            index += 1
        return
    else:
        return None


# go through all favorites, delete broken ones and attempt to fix updated cores
def refresh_favorites():
    config = read_config()
    broken = []

    index = 0
    for entry in config:
        linked = os.readlink(entry[1])
        if not os.path.exists(linked):
            broken.append(index)
        index += 1

    for idx in broken:
        entry = config[idx]
        print("Found broken favorite: {}".format(entry[1]))

        remove_favorite(idx)

        # ignore core files that aren't versioned
        if re.search("_\d{8}\.", entry[1]) is None:
            continue

        link = entry[1].rsplit("_", 1)[0]
        old_target = entry[0].rsplit("_", 1)[0]

        new_search = glob.glob("{}_*".format(old_target))
        if (len(new_search) > 0):
            new_target = new_search[0]
            new_link = "_".join([link, new_target.rsplit("_", 1)[1]])
            add_favorite(new_target, new_link)


# run a refresh on each boot
def try_add_to_startup():
    if not os.path.exists(STARTUP_SCRIPT):
        return

    with open(STARTUP_SCRIPT, "r") as f:
        if "Startup favorites" in f.read():
            return

    with open(STARTUP_SCRIPT, "a") as f:
        f.write("\n# Startup favorites\n[[ -e /media/fat/Scripts/favorites.sh ]] && /media/fat/Scripts/favorites.sh refresh\n")


# display menu to browse for and select launcher file
def display_launcher_select(start_folder):
    def menu(folder):
        args = [
            "dialog", "--title", WINDOW_TITLE, "--ok-label", "Select",
            "--menu", "Select a core to favorite.\n" + folder,
            WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1], WINDOW_DIMENSIONS[2]
        ]

        if folder != os.path.dirname(SD_ROOT):
            # restrict browsing to the /media folder
            args.extend(["1", ".."])
            all_items = [".."]
            idx = 2
        else:
            all_items = []
            idx = 1

        subfolders = []
        files = []

        # pick out and sort folders and valid files
        for i in os.listdir(folder):
            # make an exception on sd root to show a clean version
            if HIDE_SD_FILES and folder == SD_ROOT:
                if i in ALLOWED_SD_FILES:
                    subfolders.append(i)
                    continue
                else:
                    continue

            name, ext = os.path.splitext(i)

            if os.path.isdir(os.path.join(folder, i)):
                subfolders.append(i)
            elif ext in ALLOWED_FILES:
                files.append(i)

        subfolders.sort(key=str.lower)
        files.sort(key=str.lower)

        # add everything to the menu list
        for i in subfolders:
            args.extend([str(idx), "{}/".format(i)])
            all_items.append("{}/".format(i))
            idx += 1

        for i in files:
            args.extend([str(idx), i])
            all_items.append(i)
            idx +=1


        result = subprocess.run(args, stderr=subprocess.PIPE)

        selection = get_menu_output(result.stderr.decode())
        button = get_menu_output(result.returncode)

        if button == 0:
            if selection == "":
                return None
            else:
                return all_items[selection - 1]
        else:
            return None

    current_folder = start_folder
    selected = menu(current_folder)
    
    # handle browsing to another directory
    while selected is not None and (selected == ".." or selected.endswith("/")):
        if selected.endswith("/"):
            current_folder = os.path.join(current_folder, selected[:-1])
        elif selected == "..":
            current_folder = os.path.dirname(current_folder)
        selected = menu(current_folder)

    if selected is None:
        return None
    else:
        return os.path.join(current_folder, selected)


def add_favorite_workflow():
    item = display_launcher_select(SD_ROOT)
    if item is None:
        return
    
    name = display_add_favorite_name(item)
    if name is None:
        return
    
    folder = display_add_favorite_folder()
    if folder is None:
        return
    elif folder == "__ROOT__":
        folder = ""

    # TODO: check favorite doesn't already exist

    entry = [item, os.path.join(SD_ROOT, folder, name)]
    add_favorite(entry[0], entry[1])


# symlink arcade cores folder to make mra symlinks work
def setup_arcade_files():
    # TODO: validate these are correct symlinks before working on them
    cores_folder = os.path.join(SD_ROOT, "_Arcade", "cores")
    root_cores_link = os.path.join(SD_ROOT, "cores")
    if not os.path.exists(root_cores_link):
        os.symlink(cores_folder, root_cores_link)

    favs_cores_link = os.path.join(FAVORITES_FOLDER, "cores")
    if os.path.exists(FAVORITES_FOLDER) and not os.path.exists(favs_cores_link):
        os.symlink(cores_folder, favs_cores_link)


if __name__ == "__main__":
    create_favorites_folder()
    setup_arcade_files()
    try_add_to_startup()

    if len(sys.argv) == 2 and sys.argv[1] == "refresh":
        refresh_favorites()
    else:
        refresh_favorites()
        selection = display_main_menu()
        while selection is not None:
            if selection == "__ADD__":
                add_favorite_workflow()
            else:
                display_delete_favorite(selection)
            
            selection = display_main_menu()

    cleanup_favorites()