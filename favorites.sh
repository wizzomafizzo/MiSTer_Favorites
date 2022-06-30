#!/usr/bin/env python

import os
import subprocess
import sys
import glob
import re
import zipfile

# TODO: mention other scripts in readme
# TODO: shorten long filenames in menu items

FAVORITES_NAME = "_@Favorites"

SD_ROOT = "/media/fat"
FAVORITES_DB = os.path.join(SD_ROOT, "favorites.txt")
FAVORITES_FOLDER = os.path.join(SD_ROOT, FAVORITES_NAME)
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"

EXTERNAL_FOLDER = "/media/usb0"
if os.path.exists(os.path.join(EXTERNAL_FOLDER, "games")):
    EXTERNAL_FOLDER = os.path.join(EXTERNAL_FOLDER, "games")

# by default hide all the unnecessary files in the SD root when browsing
HIDE_SD_FILES = True
ALLOWED_SD_FILES = {
    "_arcade",
    "_console",
    "_computer",
    "_games",
    "_other",
    "_utility",
    "cifs",
    "games",
}

CORE_FILES = {".rbf", ".mra", ".mgl"}

# (<games folder name>, <relative rbf location>, (<set of file extensions>, <delay>, <type>, <index>)[])
MGL_MAP = (
    ("ATARI2600", "_Console/Atari7800", (({".a78", ".a26", ".bin"}, 1, "f", 1),)),
    ("ATARI7800", "_Console/Atari7800", (({".a78", ".a26", ".bin"}, 1, "f", 1),)),
    ("AtariLynx", "_Console/AtariLynx", (({".lnx"}, 1, "f", 0),)),
    ("C64", "_Computer/C64", (({".prg", ".crt", ".reu", ".tap"}, 1, "f", 1),)),
    (
        "Coleco",
        "_Console/ColecoVision",
        (({".col", ".bin", ".rom", ".sg"}, 1, "f", 0),),
    ),
    ("GAMEBOY", "_Console/Gameboy", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GBA", "_Console/GBA", (({".gba"}, 1, "f", 0),)),
    ("Genesis", "_Console/Genesis", (({".bin", ".gen", ".md"}, 1, "f", 0),)),
    ("MegaCD", "_Console/MegaCD", (({".cue", ".chd"}, 1, "s", 0),)),
    (
        "NeoGeo",
        "_Console/NeoGeo",
        (({".neo", ".zip"}, 1, "f", 1), ({".iso", ".bin"}, 1, "s", 1)),
    ),
    ("NES", "_Console/NES", (({".nes", ".fds", ".nsf"}, 1, "f", 0),)),
    ("PSX", "_Console/PSX", (({".cue", ".chd"}, 1, "s", 1),)),
    ("S32X", "_Console/S32X", (({".32x"}, 1, "f", 0),)),
    ("SMS", "_Console/SMS", (({".sms", ".sg"}, 1, "f", 1), ({".gg"}, 1, "f", 2))),
    ("SNES", "_Console/SNES", (({".sfc", ".smc"}, 2, "f", 0),)),
    (
        "TGFX16",
        "_Console/TurboGrafx16",
        (
            ({".pce", ".bin"}, 1, "f", 0),
            ({".sgx"}, 1, "f", 1),
        ),
    ),
    (
        "TGFX16-CD",
        "_Console/TurboGrafx16",
        (({".cue", ".chd"}, 1, "s", 0),),
    ),
    ("VECTREX", "_Console/Vectrex", (({".ovr", ".vec", ".bin", ".rom"}, 1, "f", 1),)),
    ("WonderSwan", "_Console/WonderSwan", (({".wsc", ".ws"}, 1, "f", 1),)),
)

GAMES_FOLDERS = (
    "/media/fat",
    "/media/usb0",
    "/media/usb1",
    "/media/usb2",
    "/media/usb3",
    "/media/usb4",
    "/media/usb5",
    "/media/fat/cifs",
)

WINDOW_TITLE = "Favorites Manager"
WINDOW_DIMENSIONS = ["20", "75", "20"]

SELECTION_HISTORY = {
    "__MAIN__": "1",
}


def get_selection(path):
    if path in SELECTION_HISTORY:
        return str(SELECTION_HISTORY[path])
    else:
        return ""


def set_selection(path, selection):
    global SELECTION_HISTORY
    SELECTION_HISTORY[path] = str(selection)


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


def add_favorite_mgl(core_path, mgl_path, mgl_data):
    config = read_config()
    entry = [core_path, mgl_path]
    with open(mgl_path, "w") as f:
        f.write(mgl_data)
    config.append(entry)
    write_config(config)


def remove_favorite(path):
    config = read_config()
    if len(config) == 0:
        return
    idx = 0
    for entry in config:
        if entry[1] == path:
            config.pop(idx)
            delete_link(entry)
            break
        idx += 1
    write_config(config)


def rename_favorite(path, new_path):
    os.rename(path, new_path)
    config = read_config()
    for entry in config:
        if entry[1] == path:
            entry[1] = new_path
            break
    write_config(config)

# generate XML contents for MGL file
def make_mgl(rbf, delay, type, index, path):
    mgl = '<mistergamedescription>\n\t<rbf>{}</rbf>\n\t<file delay="{}" type="{}" index="{}" path="{}"/>\n</mistergamedescription>'
    return mgl.format(rbf, delay, type, index, path)


def create_favorites_folder():
    if not os.path.exists(FAVORITES_FOLDER):
        os.mkdir(FAVORITES_FOLDER)


# delete any create folder and symlinks that aren't required anymore
def cleanup_favorites():
    root_cores = os.path.join(SD_ROOT, "cores")
    if (
        os.path.islink(root_cores)
        and len(glob.glob("{}{}*.mra".format(SD_ROOT, os.path.sep))) == 0
    ):
        # delete the root cores symlink if it's safe
        os.remove(root_cores)
    if os.path.exists(FAVORITES_FOLDER):
        files = os.listdir(FAVORITES_FOLDER)
        if len(files) == 0:
            os.rmdir(FAVORITES_FOLDER)
        elif len(files) == 1 and files[0] == "cores":
            # clean up favorites arcade cores symlink
            os.remove(os.path.join(FAVORITES_FOLDER, "cores"))
            os.rmdir(FAVORITES_FOLDER)


def get_menu_output(output):
    try:
        return int(output)
    except ValueError:
        return None


# return system name from mgl file
def get_mgl_system(path):
    if os.path.exists(path):
        with open(path, "r") as f:
            core = re.search("\<rbf\>.+\/(.+)\</rbf\>", f.read())
            if core:
                return core.groups()[0]


def display_main_menu():
    config = sorted(read_config(), key=lambda x: x[1].lower())

    def menu():
        args = [
            "dialog",
            "--title",
            WINDOW_TITLE,
            "--ok-label",
            "Select",
            "--cancel-label",
            "Exit",
            "--default-item",
            get_selection("__MAIN__"),
            "--menu",
            "Add a new favorite or select an existing one to modify.",
            WINDOW_DIMENSIONS[0],
            WINDOW_DIMENSIONS[1],
            WINDOW_DIMENSIONS[2],
            "1",
            "<ADD NEW FAVORITE>",
            "",
            "------------------",
        ]

        number = 2
        for entry in config:
            args.append(str(number))
            fav_file = entry[1].replace(SD_ROOT, "")
            if entry[1].endswith(".mgl"):
                system_name = get_mgl_system(entry[1])
                if system_name is not None:
                    args.append("{} [{}]".format(fav_file, system_name))
                else:
                    args.append(str(fav_file))
            else:
                args.append(str(fav_file))
            number += 1

        result = subprocess.run(args, stderr=subprocess.PIPE)

        selection = get_menu_output(result.stderr.decode())
        button = get_menu_output(result.returncode)
        set_selection("__MAIN__", selection)

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


def display_add_favorite_name(item, msg=None):
    # display a message box first if there's a problem
    if msg is not None:
        msg_args = [
            "dialog",
            "--title",
            WINDOW_TITLE,
            "--msgbox",
            msg,
            WINDOW_DIMENSIONS[0],
            WINDOW_DIMENSIONS[1],
        ]
        subprocess.run(msg_args)

    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
        "--inputbox",
        "Enter a display name for the favorite. Dates and names.txt replacements will still apply.",
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
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
    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
        "--ok-label",
        "Select",
        "--menu",
        "Select a folder to place favorite.",
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
        WINDOW_DIMENSIONS[2],
        "1",
        "<TOP LEVEL>",
        "2",
        "{}/".format(FAVORITES_NAME),
    ]

    idx = 3
    subfolders = []

    for root, dirs, files in os.walk(os.path.join(SD_ROOT, FAVORITES_NAME)):
        for item in dirs:
            path = os.path.join(root, item)
            if os.path.isdir(path) and item.startswith("_"):
                subfolders.append(path.replace(SD_ROOT + os.path.sep, ""))


    for item in sorted(subfolders, key=str.lower):
        args.append(str(idx))
        args.append("{}/".format(item))
        idx += 1

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        if selection == 1:
            return "__ROOT__"
        elif selection == 2:
            return FAVORITES_NAME
        else:
            return subfolders[selection - 3]
    else:
        return None


def display_modify_favorite(path, msg=None):
    # display a message box first if there's a problem
    if msg is not None:
        msg_args = [
            "dialog",
            "--title",
            WINDOW_TITLE,
            "--msgbox",
            msg,
            WINDOW_DIMENSIONS[0],
            WINDOW_DIMENSIONS[1],
        ]
        subprocess.run(msg_args)

    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
        "--ok-label",
        "Rename",
        "--extra-button",
        "--extra-label",
        "Delete",
        "--inputbox",
        "Enter a new display name for the favorite or delete it.",
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
    ]

    orig_name, ext = os.path.splitext(os.path.basename(path))
    args.append(orig_name)

    result = subprocess.run(args, stderr=subprocess.PIPE)

    name = str(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 3:
        # delete
        display_delete_favorite(path)
        return
    elif button == 0:
        # rename
        new_path = os.path.join(os.path.dirname(path), name + ext)
        
        if name == "":
            return display_modify_favorite(path, "Name cannot be empty.")
        elif os.path.exists(new_path):
            return display_modify_favorite(path, "Favorite with this name already exists.")

        rename_favorite(path, new_path)
        return
    else:
        # cancel
        return


def display_delete_favorite(path):
    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
        "--yesno",
        "Delete favorite {}?".format(path.replace(SD_ROOT, "")),
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE)

    button = get_menu_output(result.returncode)

    if button == 0:
        remove_favorite(path)
        return
    else:
        return None


# go through all favorites, delete broken ones and attempt to fix updated cores
def refresh_favorites():
    config = read_config()
    broken = []

    for entry in config:
        # probably an mgl file
        if not os.path.islink(entry[1]):
            continue

        linked = os.readlink(entry[1])
        if not os.path.exists(linked):
            broken.append(entry)

    for entry in broken:
        remove_favorite(entry[1])

        # ignore core files that aren't versioned
        if re.search("_\d{8}\.", entry[1]) is None:
            continue

        link = entry[1].rsplit("_", 1)[0]
        old_target = entry[0].rsplit("_", 1)[0]

        new_search = glob.glob("{}_*".format(old_target))
        if len(new_search) > 0:
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
        f.write(
            "\n# Startup favorites\n[[ -e /media/fat/Scripts/favorites.sh ]] && /media/fat/Scripts/favorites.sh refresh\n"
        )


def match_games_folder(folder: str):
    for system in MGL_MAP:
        for parent in GAMES_FOLDERS:
            base_folder = os.path.join(parent, system[0]).lower()
            games_subfolder = os.path.join(parent, "games", system[0]).lower()
            folder = folder.lower()
            if folder.startswith(base_folder) or folder.startswith(games_subfolder):
                return system[0], system
    return "__CORE__", None


# display menu to browse for and select launcher file
def display_launcher_select(start_folder):
    def menu(folder: str):
        subfolders = []
        files = []
        file_type, mgl = match_games_folder(folder)

        zip = None
        if folder.lower().endswith(".zip"):
            if not zipfile.is_zipfile(folder):
                return file_type, os.path.dirname(folder)
            zip = zipfile.ZipFile(folder)

        if zip is not None:
            dir = [x for x in zip.namelist() if "/" not in x]
        else:
            dir = os.listdir(folder)

        # pick out and sort folders and valid files
        for i in dir:
            # system roms
            if file_type != "__CORE__" and mgl is not None:
                name, ext = os.path.splitext(i)
                if os.path.isdir(os.path.join(folder, i)):
                    subfolders.append(i)
                    continue
                else:
                    for rom_type in mgl[2]:
                        if ext in rom_type[0] or ext == ".zip":
                            files.append(i)
                            break

            # make an exception on sd root to show a clean version
            if HIDE_SD_FILES and folder == SD_ROOT:
                if i.lower() in ALLOWED_SD_FILES:
                    subfolders.append(i)
                    continue
                else:
                    continue

            # default list/rbf and mra cores
            name, ext = os.path.splitext(i)
            if os.path.isdir(os.path.join(folder, i)):
                subfolders.append(i)
            elif ext in CORE_FILES:
                files.append(i)

        subfolders.sort(key=str.lower)
        files.sort(key=str.lower)

        if file_type == "__CORE__":
            msg = "Select core or game to favorite."
        else:
            msg = "Select {} rom to favorite.".format(file_type)

        args = [
            "dialog",
            "--title",
            WINDOW_TITLE,
            "--ok-label",
            "Select",
            "--default-item",
            get_selection(folder),
            "--menu",
            msg + "\n" + folder,
            WINDOW_DIMENSIONS[0],
            WINDOW_DIMENSIONS[1],
            WINDOW_DIMENSIONS[2],
        ]

        all_items = []
        idx = 1

        # shortcut to external drive
        show_external = (
            folder == SD_ROOT
            and os.path.isdir(EXTERNAL_FOLDER)
            and len(os.listdir(EXTERNAL_FOLDER)) > 0
        )
        if show_external:
            args.extend([str(idx), "<GO TO USB DRIVE>"])
            idx += 1

        # restrict browsing to the /media folder
        if folder != os.path.dirname(SD_ROOT):
            args.extend([str(idx), ".."])
            all_items = [".."]
            idx += 1

        # add everything to the menu list
        for i in subfolders:
            args.extend([str(idx), "{}/".format(i)])
            all_items.append("{}/".format(i))
            idx += 1

        for i in files:
            args.extend([str(idx), i])
            all_items.append(i)
            idx += 1

        result = subprocess.run(args, stderr=subprocess.PIPE)

        selection = get_menu_output(result.stderr.decode())
        button = get_menu_output(result.returncode)

        if zip is not None:
            zip.close()

        if button == 0:
            if selection == "":
                return None, None
            set_selection(folder, selection)

            if show_external and selection == 1:
                return file_type, EXTERNAL_FOLDER + "/"
            elif show_external:
                return file_type, all_items[selection - 2]
            else:
                return file_type, all_items[selection - 1]
        else:
            return None, None

    current_folder = start_folder
    file_type, selected = menu(current_folder)

    while True:
        if selected is None:
            return None, None
        elif selected == EXTERNAL_FOLDER + "/":
            current_folder = EXTERNAL_FOLDER
        elif selected.endswith("/"):
            current_folder = os.path.join(current_folder, selected[:-1])
        elif selected == "..":
            current_folder = os.path.dirname(current_folder)
        elif selected.lower().endswith(".zip"):
            rbf, mgl_def = mgl_from_file(file_type, selected)
            # exception for systems that actually accept zip files
            if mgl_def is not None:
                return file_type, os.path.join(current_folder, selected)
            else:
                current_folder = current_folder = os.path.join(current_folder, selected)
        else:
            return file_type, os.path.join(current_folder, selected)

        file_type, selected = menu(current_folder)


# return full path of favorite file based on user selections
def new_favorite_path(file_type, folder, name):
    if file_type == "__CORE__":
        # rbf/mra file
        return os.path.join(SD_ROOT, folder, name)
    else:
        # system rom
        basename, ext = os.path.splitext(name)
        mgl_name = basename + ".mgl"
        return os.path.join(SD_ROOT, folder, mgl_name)


# return required mgl values for file
def mgl_from_file(file_type, name):
    rbf = None
    mgl_def = None
    for system in MGL_MAP:
        if system[0] == file_type:
            rbf = system[1]
            for rom_type in system[2]:
                ext = os.path.splitext(name)[1]
                if ext.lower() in rom_type[0]:
                    mgl_def = rom_type
    return rbf, mgl_def


# return a relative rom path for mgl files
def strip_games_folder(path: str):
    items = os.path.normpath(path).split(os.path.sep)
    idx = 0
    rel_path = None
    for name in items:
        if name.lower() == "games" and (idx + 2) < len(items):
            rel_path = os.path.join(*items[(idx + 2) :])
            break
        else:
            idx += 1
    if rel_path is None:
        return path
    else:
        return rel_path


def add_favorite_workflow():
    # pick the file to be favorited
    file_type, item = display_launcher_select(SD_ROOT)
    if item is None or file_type is None:
        # cancelled
        return

    # pick the folder where the favorite goes
    folder = display_add_favorite_folder()
    if folder is None:
        # cancelled
        return
    elif folder == "__ROOT__":
        folder = ""

    # enter file/display name of the favorite
    name = display_add_favorite_name(item)
    valid_path = False
    while not valid_path:
        if name is None:
            # cancelled
            return
        path = new_favorite_path(file_type, folder, name)
        if os.path.exists(path):
            valid_path = False
            name = display_add_favorite_name(
                item, "A favorite already exists with this name."
            )
            continue
        if os.path.splitext(path)[1] == "":
            valid_path = False
            name = display_add_favorite_name(item)
            continue
        else:
            valid_path = True

    if file_type == "__CORE__":
        # rbf/mra file
        add_favorite(item, path)
    else:
        # system rom, make mgl file
        rbf, mgl_def = mgl_from_file(file_type, name)

        if rbf is None or mgl_def is None:
            # this shouldn't really happen due to the contraints on the file picker
            raise Exception("Rom file type does not match any MGL definition")

        mgl_data = make_mgl(
            rbf,
            mgl_def[1],
            mgl_def[2],
            mgl_def[3],
            ("../../../.." + item),
        )
        add_favorite_mgl(item, path, mgl_data)


# symlink arcade cores folder to make mra symlinks work
def setup_arcade_files():
    cores_folder = os.path.join(SD_ROOT, "_Arcade", "cores")

    root_cores_link = os.path.join(SD_ROOT, "cores")
    if not os.path.exists(root_cores_link):
        os.symlink(cores_folder, root_cores_link)

    favs_cores_link = os.path.join(FAVORITES_FOLDER, "cores")
    if os.path.exists(FAVORITES_FOLDER) and not os.path.exists(favs_cores_link):
        os.symlink(cores_folder, favs_cores_link)

    for root, dirs, files in os.walk(os.path.join(SD_ROOT, FAVORITES_NAME)):
        for d in dirs:
            cores_link = os.path.join(root, d, "cores")
            if not os.path.exists(cores_link):
                os.symlink(cores_folder, cores_link)


if __name__ == "__main__":
    try_add_to_startup()

    if len(sys.argv) == 2 and sys.argv[1] == "refresh":
        refresh_favorites()
    else:
        create_favorites_folder()
        setup_arcade_files()

        refresh_favorites()

        selection = display_main_menu()
        while selection is not None:
            if selection == "__ADD__":
                add_favorite_workflow()
            else:
                display_modify_favorite(selection)

            selection = display_main_menu()
        print("")

    cleanup_favorites()
