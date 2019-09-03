#!/usr/bin/env python  #前面已经识别路路由器的构架了，并将结果存入数据库中了，现在要装载路由器固件系统内容存储对象到imagetables

import tarfile  #引用Python中的各个库
import getopt
import sys
import re
import hashlib
import psycopg2
import six

def getFileHashes(infile): #实际上把实际参数./images/1.tar.gz赋值给infile形式参数
    t = tarfile.open(infile)  #打开文件
    files = list()  #初始化列表
    links = list()
    for f in t.getmembers():  #获取文件夹中的所有文件的文件名
        if f.isfile():  #如果只写文件的是文件
            # we use f.name[1:] to get rid of the . at the beginning of the path
            files.append((f.name[1:], hashlib.md5(t.extractfile(f).read()).hexdigest(),  #扩充files列表和links列表
                          #hashlib.md5()函数: 获取一个md5加密算法对象(解压文件，读出来），转换成16进制字符串
                          f.uid, f.gid, f.mode))  #获取文件的用户身份，用户组身份和权限设定子串
        elif f.issym():  #如果不是文件，
            links.append((f.name[1:], f.linkpath))
    return (files, links)  #返回元祖

def getOids(objs, cur):
    # hashes ... all the hashes in the tar file
    hashes = [x[1] for x in objs]
    hashes_str = ",".join(["""'%s'""" % x for x in hashes])
    query = """SELECT id,hash FROM object WHERE hash IN (%s)"""
    cur.execute(query % hashes_str)
    res = [(int(x), y) for (x, y) in cur.fetchall()]

    existingHashes = [x[1] for x in res]

    missingHashes = set(hashes).difference(set(existingHashes))

    newObjs = createObjects(missingHashes, cur)

    res += newObjs

    result = dict([(y, x) for (x, y) in res])
    return result

def createObjects(hashes, cur):
    query = """INSERT INTO object (hash) VALUES (%(hash)s) RETURNING id"""
    res = list()
    for h in set(hashes):
        cur.execute(query, {'hash':h})
        oid = int(cur.fetchone()[0])
        res.append((oid, h))
    return res

def insertObjectToImage(iid, files2oids, links, cur):
    query = """INSERT INTO object_to_image (iid, oid, filename, regular_file, uid, gid, permissions) VALUES (%(iid)s, %(oid)s, %(filename)s, %(regular_file)s, %(uid)s, %(gid)s, %(mode)s)"""

    cur.executemany(query, [{'iid': iid, 'oid' : x[1], 'filename' : x[0][0],
                             'regular_file' : True, 'uid' : x[0][1],
                             'gid' : x[0][2], 'mode' : x[0][3]} \
                            for x in files2oids])
    cur.executemany(query, [{'iid': iid, 'oid' : 1, 'filename' : x[0],
                             'regular_file' : False, 'uid' : None,
                             'gid' : None, 'mode' : None} \
                            for x in links])

def process(iid, infile):
    dbh = psycopg2.connect(database="firmware", user="firmadyne",
                           password="firmadyne", host="127.0.0.1")
    cur = dbh.cursor()

    (files, links) = getFileHashes(infile)

    oids = getOids(files, cur)

    fdict = dict([(h, (filename, uid, gid, mode)) \
            for (filename, h, uid, gid, mode) in files])

    file2oid = [(fdict[h], oid) for (h, oid) in six.iteritems(oids)]

    insertObjectToImage(iid, file2oid, links, cur)

    dbh.commit()

    dbh.close()

def main():
    infile = iid = None
    opts, argv = getopt.getopt(sys.argv[1:], "f:i:")
    for k, v in opts:
        if k == '-i':
            iid = int(v)
        if k == '-f':
            infile = v

    if infile and not iid:
        m = re.search(r"(\d+)\.tar\.gz", infile)
        if m:
            iid = int(m.group(1))

    process(iid, infile)

if __name__ == "__main__":
    main()
