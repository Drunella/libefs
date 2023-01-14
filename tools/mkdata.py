#!/usr/bin/env python3

# ----------------------------------------------------------------------------
# Copyright 2023 Drunella
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------

import os
import sys
import glob
import subprocess
import argparse
import hashlib
import traceback
import pprint
import random


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("-f", dest="filename", action="store", required=True, help="filename")
    p.add_argument("-a", dest="address", action="store", required=True, help="address at beginning")
    p.add_argument("-s", dest="size", action="store", required=True, help="size of random bytes.")
    args = p.parse_args()

    filepath = args.filename
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    address = int(args.address, 0)
    size = int(args.size, 0)
    
    binary_file = bytearray([0x00] * (size + 2))

    binary_file[0] = address & 0xff
    binary_file[1] = (address & 0xff00) >> 8
    
    binary_file[2:] = random.randbytes(size)
    name = os.path.splitext(os.path.basename(filepath))
    
    counter = 0
    for c in name[0]:
        binary_file[2 + counter] = ord(c)
        counter += 1
        if (counter >= size):
            break;
    if (counter < size):
        binary_file[2 + counter] = 0
    
    with open(filepath, "wb") as f:
        f.write(binary_file)

    print(filepath + ", 1")
                
    return 0

        
if __name__ == '__main__':
    try:
        retval = main(sys.argv)
        sys.exit(retval)
    except Exception as e:
        print(e)
        traceback.print_exc()
        sys.exit(1)
