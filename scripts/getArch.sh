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

function getArch() {  #getArch函数
    if (echo ${FILETYPE} | grep -q "MIPS64")  #安静模式，不打印任何标准输出。如果有匹配的内容则立即返回状态值0；“|”将两个命令隔开，管道符左边命令的输出就会作为管道符右边命令的输入
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
    if (echo ${FILETYPE} | grep -q "LSB")  #LSB最小有效字节
    then
        END="el"
    elif (echo ${FILETYPE} | grep -q "MSB")  #MSB最高有效字节
    then
        END="eb"
    else
        END=""
    fi
}

INFILE=${1}  #把第一个位置参数赋值给变量INFIlE
BASE=$(basename "$1")  #basename命令用于获取路径中的文件名或路径名,还可以对末尾字符进行删除；去除第一个位置参数的目录，把剩下的名字作为变量的值赋值给变量BASE；即获得第一个位置参数的文件名
IID=${BASE%.tar.gz}  #把tar.gz最后一个.及其右边的删除，即获取他的文件名的前缀

mkdir -p "/tmp/${IID}"  #建立/temp目录的子目录，（-p）确保/temp目录存在，不存在就建一个；然后把IID文件放在这个目录下，即构建了建立/temp目录的子目录

set +e  #执行的时候如果出现了返回值为非零将会继续执行下面的脚本
FILES="$(tar -tf $INFILE | grep -e "/busybox\$") "  #INFILE是一个变量，是一个目录，列出这个目录下的所有文件；并找到/busy/box这个目录下的文件
FILES+="$(tar -tf $INFILE | grep -E "/sbin/[[:alpha:]]+")"  #/busybox/sbin/任意字母/bin/任意字母
FILES+="$(tar -tf $INFILE | grep -E "/bin/[[:alpha:]]+")"
set -e  #执行的时候如果出现了返回值为非零，整个脚本 就会立即退出

for TARGET in ${FILES}
do
    SKIP=$(echo "${TARGET}" | fgrep targre-o / | wc -l)  #将样式视为固定字符串的列表，只显示匹配部分，即显示每一个包含上面的这个目录的变量中/的数量
    tar -xf "${INFILE}" -C "/tmp/${IID}/" --strip-components=${SKIP} ${TARGET}  #把1.tar.gz中的文件解出到/temp这个目录下，并且在解压过程中去除掉SKIP个引导部分
    TARGETLOC="/tmp/$IID/${TARGET##*/}"

    if [ -h ${TARGETLOC} ] || [ ! -f ${TARGETLOC} ]  #-h当TARGRTLOC存在并且是符号链接文件时返回真或-f当TARGRTLOC存在并且是正规文件时返回真
    then                                             #即当TARGRTLOC存在并且是符号链接文件或TARGRTLOC存在并且是正规文件（不是正规文件）
        continue                                     #一直找到TARGRTLOC是符号链接文件或不是正规文件时，就跳出循环
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
