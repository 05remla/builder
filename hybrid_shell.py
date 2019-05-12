'''
-*- coding: utf-8 -*-
#add easy help for other modules
# PYTHON <= 2.7
'''
from shutil import copy as cp
from shutil import move as mv
from os import getcwd as pwd
from os import chdir as cd
import os


def form(Object):
    Type = type(Object)
    if (Type == list):
        {print(i): i for i in Object}
    elif (Type == dict):
        for i in Object.keys():
            print('\n', '=' * 50, '\n', i.upper(), '\n', '=' * 50)
            for j in Object[i]:
                print(j)
        
            
def touch(fname, times=None):
    #Updates the modified time of a file without changing the
    #contents of it much like the touch command in 'nix systems.
    with open(fname, 'a'):
        os.utime(fname, times)



def fork(target, workload, ret=False):
    #forks thread target for each in workload using concurrent.futures
    #target is a function
    #workload is a list of commands for the target to run
    #Returns result in dictionary
    from concurrent.futures import ThreadPoolExecutor as TPoolEx

    Results = dict()
    with TPoolEx(max_workers=len(workload)) as executor:
        for num in range(len(workload)):
                future = executor.submit(target, workload[num])
                if ret: Results['return_' + str(num)] = future.result()
                    
    return Results



def cat(file, num=False):
    #Displays contents of a file to interpreter much like the
    #cat command in 'nix systems.
    contents = list()
    with open(file) as i:
        List = i.readlines()
        for j in range(len(List)):
            if num:
                output = str(j + 1) + ' ' + List[j].strip('\n')
            else:
                output = List[j].strip('\n')                
            contents.append(output)
    return contents



def stringX(Command, shell=False, decode='utf-8'):
    #Runs a system command without forking from python.
    #Able to return output of a given command to interpreter.
    #Returns a generator object    
    from shlex import split as shlexSplit
    from subprocess import PIPE, Popen
    
    Command = shlexSplit(Command)
    p = Popen(Command,
              stdout=PIPE,
              shell=shell,
              bufsize=1)

    Return = []
    for line in iter(p.stdout.readline, b''):
        Return.append(line.strip().decode(decode))
    
    return Return
    p.communicate()



def find(pattern, items, sensitive=False):
    #Returns matching items of a query. "pattern" must match "item(s)"
    #Capable of searching directories as well as lists implicitly.
    if sensitive: from fnmatch import fnmatchcase as fnmatch
    else: from fnmatch import fnmatch
    results = list()

    try:
        for root, dirs, files in os.walk(items):
            for name in dirs:
                if fnmatch(name, pattern):
                    results.append(os.path.join(root, name))
                    
            for name in files:
                if fnmatch(name, pattern):
                    results.append(os.path.join(root, name))
    except:
        for i in items:
            if fnmatch(i, pattern):
                results.append(i)

    return results



def ls(path='.', details=['type'], absPath=False, pattern='*'):
    #Lists contents of a given directory with some bells and whistles.
    #details:
    #requested detail types are defined in a list.
    #Valid detail types are...
    #
    #mode ino dev nlink uid gid size atime mtime ctime type
    from fnmatch import fnmatch
    from time import ctime
    from stat import S_ISREG
    from stat import S_ISDIR

    LIST = os.listdir(path)
    masterList = list()
    for i in LIST:
        try:
            fileList = list()
            if fnmatch(i, pattern):
                i = os.path.abspath(path + os.sep + i)
                fileList.append(i)
                detailsList = (str(os.stat(i).st_mode), str(os.stat(i).st_ino),
                            str(os.stat(i).st_dev), str(os.stat(i).st_nlink),
                            str(os.stat(i).st_uid), str(os.stat(i).st_gid),
                            "{:,}".format(int(round(os.stat(i).st_size / 1000))) + 'KB',
                            ctime(int(os.stat(i).st_atime)),
                            ctime(int(os.stat(i).st_mtime)),
                            ctime(int(os.stat(i).st_ctime)))
    
                if S_ISDIR(int(detailsList[0])):
                    detailsList = detailsList + ('dir',)
                elif S_ISREG(int(detailsList[0])):
                    detailsList = detailsList + ('file',)
    
                types = ['mode', 'ino', 'dev', 'nlink', 'uid', 'gid',
                         'size', 'atime', 'mtime', 'ctime', 'type']
    
                for j in details:
                    for k in range(len(types)):
                        if (j == types[k]):
                            fileList.append(detailsList[k])
    
            if (fileList != []):
                masterList.append(fileList)
        except:
            masterList.append([i, 'ERROR'])
        
    if not absPath:
        for i in range(len(masterList)):
            file = os.path.basename(masterList[i][0])
            masterList[i].remove(masterList[i][0])
            masterList[i].insert(0, file)

    return masterList



if __name__ == "__main__":
    pass
