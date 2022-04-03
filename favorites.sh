#!/usr/bin/env python

import os
import subprocess
import sys
import glob

SD_ROOT = "/media/fat"
FAVORITES_DB = os.path.join(SD_ROOT, "favorites.txt")
FAVORITES_FOLDER = os.path.join(SD_ROOT, "_@Favorites")
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"

WINDOW_TITLE = "Favorites Manager"
WINDOW_DIMENSIONS = ["20", "75", "20"]


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


def write_config(favorites):
    with open(FAVORITES_DB, "w") as f:
        for entry in favorites:
            f.write("{}\t{}\n".format(entry[0], entry[1]))


def create_link(entry):
    os.symlink(entry[0], entry[1])


def delete_link(entry):
    os.remove(entry[1])


def link_valid(entry):
    if os.path.islink(entry[1]):
        path = os.readlink(entry[1])
    else:
        return False


def get_cores():
    cores = []
    for root_fn in os.listdir(SD_ROOT):
        root_path = os.path.join(SD_ROOT, root_fn)
        if root_fn.endswith(".rbf") and root_fn != "menu.rbf":
            cores.append(root_path)
        elif root_fn.startswith("_") and os.path.isdir(root_path):
            for sub_fn in os.listdir(root_path):
                sub_path = os.path.join(root_path, sub_fn)
                if sub_fn.endswith(".rbf"):
                    cores.append(sub_path)
    return cores


def add_favorite(core_path, favorite_path):
    config = read_config()
    entry = [core_path, favorite_path]
    create_link(entry)
    config.append(entry)
    write_config(config)


def remove_favorite(index):
    config = read_config()
    if len(config) == 0 or len(config) < index:
        return
    entry = config.pop(index)
    delete_link(entry)
    write_config(config)


def create_favorites_folder():
    if not os.path.exists(FAVORITES_FOLDER):
        os.mkdir(FAVORITES_FOLDER)


def remove_empty_favorites_folder():
    if os.path.exists(FAVORITES_FOLDER):
        if len(os.listdir(FAVORITES_FOLDER)) == 0:
            os.rmdir(FAVORITES_FOLDER)


def get_menu_output(output):
    try:
        return int(output)
    except ValueError:
        return None


def display_main_menu():
    args = [
        "dialog", "--title", WINDOW_TITLE, 
        "--ok-label", "Select", "--cancel-label", "Exit",
        "--menu", "Add a new favorite or select an existing one to delete it.",
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1], WINDOW_DIMENSIONS[2],
        "1", "<ADD A NEW FAVORITE>"
    ]

    config = read_config()

    number = 2
    for entry in config:
        args.append(str(number))
        args.append(str(entry[1].replace(SD_ROOT, "")))
        number += 1

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)
    
    if button == 0:
        if selection == 1:
            return "ADD"
        else:
            return config[selection - 2][1]
    else:
        return None


def display_add_favorite_cores():
    cores = get_cores()
    args = [
        "dialog", "--title", WINDOW_TITLE, "--menu", "Select a core to favorite.",
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1], WINDOW_DIMENSIONS[2]
    ]

    number = 1
    for core in cores:
        args.append(str(number))
        args.append(str(core.replace(SD_ROOT, "")))
        number +=1

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        return cores[selection - 1]
    else:
        return None


def display_add_favorite_name(core):
    args = [
        "dialog", "--title", WINDOW_TITLE, "--inputbox", "Enter a display name for the favorite. Dates and names.txt replacements will still apply.",
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1]
    ]

    args.append(os.path.split(core)[-1].rstrip(".rbf"))

    result = subprocess.run(args, stderr=subprocess.PIPE)

    name = str(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        return name
    else:
        return None


def display_add_favorite_folder():
    args = [
        "dialog", "--title", WINDOW_TITLE, "--ok-label", "Select",
        "--menu", "Select a folder to place favorite.",
        WINDOW_DIMENSIONS[0], WINDOW_DIMENSIONS[1], WINDOW_DIMENSIONS[2],
        "1", "<TOP LEVEL>"
    ]

    folders = []
    for folder in os.listdir(SD_ROOT):
        if folder.startswith("_"):
            folders.append(folder)

    number = 2
    for folder in folders:
        args.append(str(number))
        args.append(str(folder.replace(SD_ROOT, "")))
        number +=1

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        if selection == 1:
            return "ROOT"
        else:
            return folders[selection - 2]
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


def add_favorite_workflow():
    core = display_add_favorite_cores()
    if core is None:
        return
    
    name = display_add_favorite_name(core)
    if name is None:
        return
    
    folder = display_add_favorite_folder()
    if folder is None:
        return
    elif folder == "ROOT":
        folder = ""

    entry = [core, os.path.join(SD_ROOT, folder, "{}.rbf".format(name))]
    add_favorite(entry[0], entry[1])


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
        print("Refreshing broken favorite: {}".format(entry[1]))

        remove_favorite(idx)

        link = entry[1].rsplit("_", 1)[0]
        old_target = entry[0].rsplit("_", 1)[0]

        new_search = glob.glob("{}_*".format(old_target))
        if (len(new_search) > 0):
            new_target = new_search[0]
            new_link = "_".join([link, new_target.rsplit("_", 1)[1]])
            add_favorite(new_target, new_link)


def add_to_startup():
    with open(STARTUP_SCRIPT, "r") as f:
        if "Startup favorites" in f.read():
            return

    with open(STARTUP_SCRIPT, "a") as f:
        f.write("\n# Startup favorites\n[[ -e /media/fat/Scripts/favorites.sh ]] && /media/fat/Scripts/favorites.sh refresh\n")


if __name__ == "__main__":
    create_favorites_folder()
    add_to_startup()

    if len(sys.argv) == 2 and sys.argv[1] == "refresh":
        refresh_favorites()
    else:
        refresh_favorites()
        selection = display_main_menu()
        while selection is not None:
            if selection == "ADD":
                add_favorite_workflow()
            else:
                display_delete_favorite(selection)
            
            selection = display_main_menu()

    remove_empty_favorites_folder()