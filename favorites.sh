#!/usr/bin/env python

from email.policy import default
import os
import subprocess
import sys
import glob
import re
import zipfile

FAVORITES_DEFAULT = "_@Favorites"
FAVORITES_NAMES = {"fav"}

SD_ROOT = "/media/fat"
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
    ("GAMEBOY2P", "_Console/Gameboy2P", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GAMEBOY", "_Console/Gameboy", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GBA2P", "_Console/GBA2P", (({".gba"}, 1, "f", 0),)),
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
        "TGFX16-CD",
        "_Console/TurboGrafx16",
        (({".cue", ".chd"}, 1, "s", 0),),
    ),
    (
        "TGFX16",
        "_Console/TurboGrafx16",
        (
            ({".pce", ".bin"}, 1, "f", 0),
            ({".sgx"}, 1, "f", 1),
        ),
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

BAD_CHARS = '<>:"/\|?*'


def get_selection(path):
    if path in SELECTION_HISTORY:
        return str(SELECTION_HISTORY[path])
    else:
        return ""


def set_selection(path, selection):
    global SELECTION_HISTORY
    SELECTION_HISTORY[path] = str(selection)


def relative_path(s):
    return s.replace(SD_ROOT + os.path.sep, "")


# characters that aren't allowed in a filename
def has_bad_chars(s):
    return any(i in s for i in BAD_CHARS)


def is_favorite_file(path):
    name, ext = os.path.splitext(path)
    ext = ext.lower()
    if ext == ".mgl":
        return True
    elif (ext == ".rbf" or ext == ".mra") and os.path.islink(path):
        return True
    else:
        return False


# check if symlink goes to an existing file
def link_valid(entry):
    if os.path.islink(entry[1]):
        path = os.readlink(entry[1])
    else:
        return False


def get_favorite_target(path):
    name, ext = os.path.splitext(path)
    if os.path.islink(path):
        return os.readlink(path)
    elif ext == ".mgl":
        with open(path, "r") as f:
            match = re.search(r'path="\.\./\.\./\.\./\.\.(.+)"', f.read())
            if match:
                return match.group(1)
            else:
                return ""
    else:
        return ""


def get_favorite_folders():
    folders = []

    for i in os.listdir(SD_ROOT):
        path = os.path.join(SD_ROOT, i)
        for part in FAVORITES_NAMES:
            if os.path.isdir(path) and i.startswith("_") and part in i.lower():
                folders.append(path)

    return folders


def get_favorites():
    favorites = []

    for i in os.listdir(SD_ROOT):
        path = os.path.join(SD_ROOT, i)
        if is_favorite_file(path):
            favorites.append([get_favorite_target(path), path])

    for folder in get_favorite_folders():
        for root, dirs, files in os.walk(folder):
            for file in files:
                path = os.path.join(root, file)
                if is_favorite_file(path):
                    favorites.append([get_favorite_target(path), path])

    return favorites


def add_favorite(core_path, favorite_path):
    os.symlink(core_path, favorite_path)


def add_favorite_mgl(core_path, mgl_path, mgl_data):
    entry = [core_path, mgl_path]
    with open(mgl_path, "w") as f:
        f.write(mgl_data)


def remove_favorite(path):
    if is_favorite_file(path):
        os.remove(path)


def rename_favorite(path, new_path):
    os.rename(path, new_path)


# generate XML contents for MGL file
def make_mgl(rbf, delay, type, index, path):
    mgl = '<mistergamedescription>\n\t<rbf>{}</rbf>\n\t<file delay="{}" type="{}" index="{}" path="{}"/>\n</mistergamedescription>'
    return mgl.format(rbf, delay, type, index, path)


def create_default_favorites():
    default_path = os.path.join(SD_ROOT, FAVORITES_DEFAULT)
    if len(get_favorite_folders()) == 0 and not os.path.exists(default_path):
        os.mkdir(default_path)


def cleanup_default_favorites():
    default_path = os.path.join(SD_ROOT, FAVORITES_DEFAULT)
    if os.path.exists(default_path) and len(os.listdir(default_path)) == 0:
        os.rmdir(default_path)

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
    config = get_favorites()

    for folder in get_favorite_folders():
        for root, dirs, files in os.walk(folder):
            for dir in dirs:
                path = os.path.join(root, dir)
                if dir.startswith("_"):
                    config.append(["", path])

    config.sort(key=lambda x: x[1].lower())

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
            "--extra-button",
            "--extra-label",
            "Create Folder",
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

        if len(config) == 0:
            args.append("")
            args.append("No favorites found.")

        number = 2
        for entry in config:
            args.append(str(number))
            fav_file = relative_path(entry[1])
            name, ext = os.path.splitext(fav_file)

            if os.path.isdir(entry[1]):
                name = name + "/"

            if len(name) >= 65:
                display = "..." + name[-62:]
            else:
                display = name

            args.append(display)
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
    elif button == 3:
        display_create_folder()
        return display_main_menu()
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


def display_edit_folder_name(parent, default_name=None, msg=None):
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
        "Enter a name for the folder. It must start with an underscore (_).",
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
        default_name or "_",
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE)
    name = str(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        if not name.startswith("_"):
            return display_edit_folder_name(
                parent, msg="Name must start with an underscore (_)."
            )
        elif name == "_":
            return display_edit_folder_name(parent, msg="Display name cannot be empty.")
        elif has_bad_chars(name):
            return display_edit_folder_name(
                parent,
                default_name=name,
                msg="Name cannot contain any of these characters: " + BAD_CHARS,
            )
        elif os.path.exists(os.path.join(parent, name)):
            return display_edit_folder_name(
                parent, default_name=name, msg="Folder with this name already exists."
            )
        else:
            return os.path.join(parent, name)
    else:
        return


def display_create_folder():
    parent = display_add_favorite_folder(
        include_root=False, msg="Select a parent folder for the new folder."
    )
    if parent is None:
        return

    path = display_edit_folder_name(os.path.join(SD_ROOT, parent))
    if path is None:
        return

    os.mkdir(path)
    setup_arcade_files()


def display_add_favorite_folder(
    include_root=True, msg="Select a folder to place favorite.", ignore_path=None
):
    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
    ]

    if include_root:
        args = args + [
            "--extra-button",
            "--extra-label",
            "Create Folder",
        ]

    args = args + [
        "--ok-label",
        "Select",
        "--menu",
        msg,
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
        WINDOW_DIMENSIONS[2],
    ]

    if include_root:
        args.append("1")
        args.append("<TOP LEVEL>")
        idx = 2
    else:
        idx = 1

    favorite_folders = get_favorite_folders()
    folders = []

    for folder in favorite_folders:
        folders.append(relative_path(folder))
        for root, dirs, files in os.walk(folder):
            for d in dirs:
                path = os.path.join(root, d)
                if os.path.isdir(path) and d.startswith("_") and path != ignore_path:
                    folders.append(relative_path(path))

    folders.sort(key=str.lower)

    for item in folders:
        args.append(str(idx))
        args.append("{}/".format(item))
        idx += 1

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        if include_root and selection == 1:
            return "__ROOT__"
        elif include_root:
            return folders[selection - 2]
        else:
            return folders[selection - 1]
    elif button == 3:
        display_create_folder()
        return display_add_favorite_folder()
    else:
        return None


def display_edit_favorite_name(path, msg=None, default_name=None):
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
        "Enter a display name for the favorite. Dates and names.txt replacements will apply.",
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
    ]

    orig_name, ext = os.path.splitext(os.path.basename(path))
    if default_name:
        args.append(default_name)
    else:
        args.append(orig_name)

    result = subprocess.run(args, stderr=subprocess.PIPE)

    name = str(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        new_path = os.path.join(os.path.dirname(path), name + ext)

        if name == "":
            return display_edit_favorite_name(path, msg="Name cannot be empty.")
        elif has_bad_chars(name):
            return display_edit_favorite_name(
                path,
                msg="Name cannot contain any of these characters: " + BAD_CHARS,
                default_name=name,
            )
        elif os.path.exists(new_path):
            return display_edit_favorite_name(
                path, msg="Favorite with this name already exists.", default_name=name
            )

        rename_favorite(path, new_path)


def display_delete_favorite(path):
    if os.path.isdir(path) and len(os.listdir(path)) > 1:
        msg_args = [
            "dialog",
            "--title",
            WINDOW_TITLE,
            "--msgbox",
            "Folder is not empty.",
            WINDOW_DIMENSIONS[0],
            WINDOW_DIMENSIONS[1],
        ]
        subprocess.run(msg_args)
        return

    if os.path.isdir(path):
        msg = f"Delete folder {relative_path(path)}?"
    else:
        msg = f"Delete favorite {relative_path(path)}?"

    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
        "--yesno",
        msg,
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE)

    button = get_menu_output(result.returncode)

    if button == 0:
        if os.path.isdir(path):
            os.remove(os.path.join(path, "cores"))
            os.rmdir(path)
        else:
            remove_favorite(path)


def display_modify_item(path):
    name, ext = os.path.splitext(os.path.basename(path))
    ext = ext.lower()

    info = f"Name: {name}\n"

    folder = relative_path(os.path.dirname(path))
    if folder == SD_ROOT:
        folder = "<TOP LEVEL>"
    info += f"Folder: {folder}\n"

    if ext == ".rbf":
        info += "Type: Core\n"
    elif ext == ".mra":
        info += "Type: Arcade Core\n"
    elif ext == ".mgl":
        info += "Type: Game\n"
        info += f"System: {get_mgl_system(path)}\n"

    if os.path.isdir(path):
        info += "Type: Folder\n"
    else:
        info += f"File: {get_favorite_target(path)}"

    args = [
        "dialog",
        "--title",
        WINDOW_TITLE,
        "--ok-label",
        "Select",
        "--menu",
        info,
        WINDOW_DIMENSIONS[0],
        WINDOW_DIMENSIONS[1],
        WINDOW_DIMENSIONS[2],
        "1",
        "Rename",
        "2",
        "Move",
        "3",
        "Delete",
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE)

    selection = get_menu_output(result.stderr.decode())
    button = get_menu_output(result.returncode)

    if button == 0:
        if selection == 1:
            if os.path.isdir(path):
                new_path = display_edit_folder_name(os.path.dirname(path), default_name=name)
                if new_path:
                    os.rename(path, new_path)
            else:
                display_edit_favorite_name(path)
        elif selection == 2:
            folder = display_add_favorite_folder(
                include_root=not os.path.isdir(path), ignore_path=path
            )
            if folder is not None:
                if folder == "__ROOT__":
                    folder = ""
                os.rename(path, os.path.join(SD_ROOT, folder, os.path.basename(path)))
        elif selection == 3:
            display_delete_favorite(path)


# go through all favorites, delete broken ones and attempt to fix updated cores
def refresh_favorites():
    broken = []

    for entry in get_favorites():
        # probably an mgl file
        if not os.path.islink(entry[1]):
            target = get_favorite_target(entry[1])
            if target != "" and not os.path.exists(target):
                remove_favorite(entry[1])
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
        if has_bad_chars(name):
            valid_path = False
            name = display_add_favorite_name(
                item,
                "Name cannot contain any of these characters: {}".format(BAD_CHARS),
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

    for folder in get_favorite_folders():
        root_cores_link = os.path.join(SD_ROOT, "cores")
        if not os.path.exists(root_cores_link):
            os.symlink(cores_folder, root_cores_link)
        for root, dirs, files in os.walk(folder):
            for d in dirs:
                cores_link = os.path.join(root, d, "cores")
                if not os.path.exists(cores_link):
                    os.symlink(cores_folder, cores_link)


if __name__ == "__main__":
    try_add_to_startup()

    if len(sys.argv) == 2 and sys.argv[1] == "refresh":
        refresh_favorites()
    else:
        create_default_favorites()
        setup_arcade_files()

        refresh_favorites()

        selection = display_main_menu()
        while selection is not None:
            if selection == "__ADD__":
                add_favorite_workflow()
            else:
                display_modify_item(selection)

            selection = display_main_menu()
        print("")