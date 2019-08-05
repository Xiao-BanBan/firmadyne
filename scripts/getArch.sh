#!/bin/bash

set -e  #告诉bash如果任何语句的执行结果不是true则退出；set -o errexit
set -u  #可以让脚本遇到错误时停止执行，并指出错误的行数信息；set -o nounset

if [ -e ./firmadyne.config ]; then  #如果存在firmadyne文件（配置文件——config文件），就为真，那么执行
    source ./firmadyne.config  #使Shell读入指定的Shell程序文件并依次执行文件中的所有语句；source命令通常用于重新执行刚修改的初始化文件，使之立即生效，而不必注销并重新登录
elif [ -e ../firmadyne.config ]; then  #如果当前界面的父级目录（即当前目录点击返回之后的目录）中有firmadyne文件，则执行
    source ../firmadyne.config  #则执行这个文件
else  #如果都不是
    echo "Error: Could not find 'firmadyne.config'!"  #输出提示信息
    exit 1  #非正常运行导致退出程序
fi  #类似于Python里的end，判断语句好像必须以fi为结尾

function getArch() {
    if (echo ${FILETYPE} | grep -q "MIPS64")
    then
        ARCH="mips64"
    elif (echo ${FILETYPE} | grep -q "MIPS")
    then
        ARCH="mips"
    elif (echo ${FILETYPE} | grep -q "ARM64")
    then
        ARCH="arm64"
    elif (echo ${FILETYPE} | grep -q "ARM")
    then
        ARCH="arm"
    elif (echo ${FILETYPE} | grep -q "Intel 80386")
    then
        ARCH="intel"
    elif (echo ${FILETYPE} | grep -q "x86-64")
    then
        ARCH="intel64"
    elif (echo ${FILETYPE} | grep -q "PowerPC")
    then
        ARCH="ppc"
    else
        ARCH=""
    fi
}

function getEndian() {
    if (echo ${FILETYPE} | grep -q "LSB")
    then
        END="el"
    elif (echo ${FILETYPE} | grep -q "MSB")
    then
        END="eb"
    else
        END=""
    fi
}

INFILE=${1}
BASE=$(basename "$1")
IID=${BASE%.tar.gz}

mkdir -p "/tmp/${IID}"

set +e
FILES="$(tar -tf $INFILE | grep -e "/busybox\$") "
FILES+="$(tar -tf $INFILE | grep -E "/sbin/[[:alpha:]]+")"
FILES+="$(tar -tf $INFILE | grep -E "/bin/[[:alpha:]]+")"
set -e

for TARGET in ${FILES}
do
    SKIP=$(echo "${TARGET}" | fgrep -o / | wc -l)
    tar -xf "${INFILE}" -C "/tmp/${IID}/" --strip-components=${SKIP} ${TARGET}
    TARGETLOC="/tmp/$IID/${TARGET##*/}"

    if [ -h ${TARGETLOC} ] || [ ! -f ${TARGETLOC} ]
    then
        continue
    fi

    FILETYPE=$(file ${TARGETLOC})

    echo -n "${TARGET}: "
    getArch
    getEndian

    if [ -n "${ARCH}" ] && [ -n "${END}" ]
    then
        ARCHEND=${ARCH}${END}
        echo ${ARCHEND}

        psql -d firmware -U firmadyne -h 127.0.0.1 -q -c "UPDATE image SET arch = '$ARCHEND' WHERE id = $IID;"

        rm -fr "/tmp/${IID}"
        exit 0
    else
        echo -n ${ARCH}
        echo ${END}
    fi
done

rm -fr "/tmp/${IID}"

exit 1
