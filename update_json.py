#!/usr/bin/env python

# Author: Wilfried JEANNIARD 2022 https://github.com/willoucom
# This work is licensed under the Creative Commons Attribution 4.0 International License. 
# To view a copy of this license, visit http://creativecommons.org/licenses/by/4.0/ 
# or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.

import os
import json
import hashlib
import calendar
import time

# Json file to be parsed 
file_json = "favorites.json"


# Get hash of the file
def hash_file(path):
    with open(path, "rb") as f:
        file_hash = hashlib.md5()
        chunk = f.read(8192)
        while chunk:
            file_hash.update(chunk)
            chunk = f.read(8192)
        return file_hash.hexdigest()


def main():
    # open Json
    with open(file_json, 'r') as f:
        data = json.load(f)

    for file in data["files"]:
        # Find the file
        if os.path.exists(file):
            filename = file
        elif os.path.exists(os.path.basename(file)):
            filename = os.path.basename(file)
        else:
            print("File not found: {}".format(file))
            continue

        # Update filesize
        size = os.path.getsize(filename)
        data["files"][file]['size'] = size
        # Update hash
        file_hash = hash_file(filename)
        data["files"][file]['hash'] = file_hash

    # Update timestamp
    data["timestamp"] = calendar.timegm(time.gmtime())

    # Serializing json
    json_object = json.dumps(data, indent=4)

    # Writing Json
    with open(file_json, "w") as outfile:
        outfile.write(json_object)


if __name__ == "__main__":
    main()
