#!/bin/bash  创建路由器固件的QEMU磁盘镜像

set -e
set -u

if [ -e ./firmadyne.config ]; then  #如果./firmadyne.config这个配置文件存在，则为真
    source ./firmadyne.config  #重新执行刚修改的初始化文件，使之立即生效，而不必注销并重新登录
elif [ -e ../firmadyne.config ]; then  #如果./firmadyneg的上一级目录中这个配置文件存在，则为真
    source ../firmadyne.config
else
    echo "Error: Could not find 'firmadyne.config'!"
    exit 1
fi

if check_number $1; then
    echo "Usage: makeImage.sh <image ID> [<architecture]"
    exit 1
fi
IID=${1}

if check_root; then
    echo "Error: This script requires root privileges!"
    exit 1
fi

if [ $# -gt 1 ]; then  #传给脚本的参数个数看看是否大于1
    if check_arch "${2}"; then  #第二个位置参数checf_arch一下
        echo "Error: Invalid architecture!"
        exit 1
    fi

    ARCH=${2}
else  #如果未知参数不大于1
    echo -n "Querying database for architecture... "  #不换行输出
    ARCH=$(psql -d firmware -U firmadyne -h 127.0.0.1 -t -q -c "SELECT arch from image WHERE id=${1};")
    #-d （datebase）指定要连接的数据库，数据库为firmware -U指定数据库用户名为firmadyne 
    #-h（host）指定要连接的主机名，数据库服务器主机或socket目录(默认："本地接口") -q 以沉默模式运行(不显示消息，只有查询结果)
    #-t --tuples-only只打印记录i  -c执行单一命令(SQL或内部指令)然后结束  找到image（猜测可能是个列表）中id是第一个位置参数，把他的arch挑出来
    ARCH="${ARCH#"${ARCH%%[![:space:]]*}"}"  #[![:space:]]匹配空白字符（空格和水平制表符）
    echo "${ARCH}"
    if [ -z "${ARCH}" ]; then
        echo "Error: Unable to lookup architecture. Please specify {armel,mipseb,mipsel} as the second argument!"
        exit 1
    fi
fi

echo "----Running----"
WORK_DIR=`get_scratch ${IID}`
IMAGE=`get_fs ${IID}`
IMAGE_DIR=`get_fs_mount ${IID}`
CONSOLE=`get_console ${ARCH}`
LIBNVRAM=`get_nvram ${ARCH}`

echo "----Copying Filesystem Tarball----"
mkdir -p "${WORK_DIR}"
chmod a+rwx "${WORK_DIR}"
chown -R "${USER}" "${WORK_DIR}"
chgrp -R "${USER}" "${WORK_DIR}"

if [ ! -e "${WORK_DIR}/${IID}.tar.gz" ]; then
    if [ ! -e "${TARBALL_DIR}/${IID}.tar.gz" ]; then
        echo "Error: Cannot find tarball of root filesystem for ${IID}!"
        exit 1
    else
        cp "${TARBALL_DIR}/${IID}.tar.gz" "${WORK_DIR}/${IID}.tar.gz"
    fi
fi

echo "----Creating QEMU Image----"
qemu-img create -f raw "${IMAGE}" 1G
chmod a+rw "${IMAGE}"

echo "----Creating Partition Table----"
echo -e "o\nn\np\n1\n\n\nw" | /sbin/fdisk "${IMAGE}"

echo "----Mounting QEMU Image----"
DEVICE=$(get_device "$(kpartx -a -s -v "${IMAGE}")")
sleep 1

echo "----Creating Filesystem----"
mkfs.ext2 "${DEVICE}"
sync

echo "----Making QEMU Image Mountpoint----"
if [ ! -e "${IMAGE_DIR}" ]; then
    mkdir "${IMAGE_DIR}"
    chown "${USER}" "${IMAGE_DIR}"
fi

echo "----Mounting QEMU Image Partition 1----"
mount "${DEVICE}" "${IMAGE_DIR}"

echo "----Extracting Filesystem Tarball----"
tar -xf "${WORK_DIR}/$IID.tar.gz" -C "${IMAGE_DIR}"
rm "${WORK_DIR}/${IID}.tar.gz"

echo "----Creating FIRMADYNE Directories----"
mkdir "${IMAGE_DIR}/firmadyne/"
mkdir "${IMAGE_DIR}/firmadyne/libnvram/"
mkdir "${IMAGE_DIR}/firmadyne/libnvram.override/"

echo "----Patching Filesystem (chroot)----"
cp $(which busybox) "${IMAGE_DIR}"
cp "${SCRIPT_DIR}/fixImage.sh" "${IMAGE_DIR}"
chroot "${IMAGE_DIR}" /busybox ash /fixImage.sh
rm "${IMAGE_DIR}/fixImage.sh"
rm "${IMAGE_DIR}/busybox"

echo "----Setting up FIRMADYNE----"
cp "${CONSOLE}" "${IMAGE_DIR}/firmadyne/console"
chmod a+x "${IMAGE_DIR}/firmadyne/console"
mknod -m 666 "${IMAGE_DIR}/firmadyne/ttyS1" c 4 65

cp "${LIBNVRAM}" "${IMAGE_DIR}/firmadyne/libnvram.so"
chmod a+x "${IMAGE_DIR}/firmadyne/libnvram.so"

cp "${SCRIPT_DIR}/preInit.sh" "${IMAGE_DIR}/firmadyne/preInit.sh"
chmod a+x "${IMAGE_DIR}/firmadyne/preInit.sh"

echo "----Unmounting QEMU Image----"
sync
umount "${DEVICE}"
kpartx -d "${IMAGE}"
losetup -d "${DEVICE}" &>/dev/null
dmsetup remove $(basename "$DEVICE") &>/dev/null
