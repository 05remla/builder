# -*- coding: utf-8 -*-
from hybrid_shell import cat, stringX
File = "/home/leo/IMAGE_BUILD_DIRECTORY/package_install_list.txt"

def CheckDups():
    global File
    dup_list = list()
    Packages_seen = set() # holds lines already seen
    for Item in cat(File, num=True):
        Package = Item.split()[1].strip()
        Num = Item.split()[0]
        if Package not in Packages_seen: # not a duplicate
            Packages_seen.add(Package)
        else:
            dup_list.append(Num + ' ' + Package)

    if not (dup_list == []):
        print('Duplicate packages were found...')
        {print(i): i for i in dup_list}
        print()

def TestNames():
    global File
    print('Checking package availability...')
    for i in cat(File):
        Comand = 'sudo apt-get -s -qq install "' + i.strip() + '"'
        stringX(Comand)
        
if __name__ == "__main__":
    CheckDups()
    TestNames()