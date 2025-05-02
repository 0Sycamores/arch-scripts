#!/bin/bash

clear

# 定义颜色代码
CYAN='\e[1;36m'
GREEN='\e[1;32m'
RED='\e[1;31m'
WHITE='\e[1;37m'
MAGENTA='\e[1;35m'
YELLOW='\e[1;33m'
NC='\e[0m'

# 定义标签
CNT="[NOTE]"
COK="[OK]"
CER="[ERROR]"
CAT="[ATTENTION]"
CWR="[WARNING]"
CAC="[ACTION]"

# 颜色输出函数
color_echo() {
    local color="$1"
    local label="$2"
    local message="$3"
    echo -e "${color}${label} ${message}${NC}"
}

color_echo $CYAN $CNT "该脚本仅适用于 Arch Linux 系统安装"

# 检查网络连接
color_echo $CYAN $CNT "正在检查网络连接..."
if ! ping -c 3 baidu.com &>/dev/null; then
    color_echo $RED $CER "网络未连接, 请连接网络后再执行此脚本"
    color_echo $YELLOW $CAT "使用的是无线网络, 请使用 iwctl 命令或者 nmtui 连接 Wi-Fi, 或使用 USB 网络共享, 虚拟机设置桥接网络"
    exit 1
else
    color_echo $GREEN $COK "网络连接正常"
fi
echo

# 禁用 reflector 服务
color_echo $CYAN $CNT "正在停止 reflector 服务..."
systemctl stop reflector.service
color_echo $GREEN $COK "reflector 服务已停止"
echo

# 验证 UEFI 引导
color_echo $CYAN $CNT "正在验证 UEFI 引导..."
if [ -f "/sys/firmware/efi/fw_platform_size" ]; then
    # 文件存在，系统是以 UEFI 模式启动的
    platform_size=$(cat "/sys/firmware/efi/fw_platform_size" 2>/dev/null)
    color_echo "$GREEN" "$COK" "系统以 UEFI 模式启动，固件位数：${platform_size} 位"
else
    # 文件不存在，系统是以 BIOS 模式启动的
    color_echo "$RED" "$CER" "系统以 BIOS (Legacy) 模式启动, 请修改 BIOS 设置为 UEFI 模式"
    exit 1
fi
color_echo $GREEN $COK "UEFI 引导验证完成"
echo

# 设置时间日期
color_echo $CYAN $CNT "正在设置时间日期..."
timedatectl set-ntp true
timedatectl set-timezone Asia/Shanghai
color_echo $GREEN $COK "时间日期设置完成"
echo

# 配置镜像源
color_echo $CYAN $CNT "正在配置镜像源..."
cat >/etc/pacman.d/mirrorlist <<EOF
Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch
Server = http://mirror.lzu.edu.cn/archlinux/\$repo/os/\$arch
EOF
color_echo $GREEN $COK "镜像源配置完成"
echo

# 询问分区目标磁盘
color_echo $CYAN $CNT "即将进行磁盘分区操作"
lsblk
read -p "请输入目标磁盘 (例如 /dev/sda 或 /dev/nvme0n1): " TARGET_DISK
if [ ! -b "$TARGET_DISK" ]; then
    color_echo $RED $CER "目标磁盘不存在，请检查设备名称"
    exit 1
fi

# 计算交换分区大小 (等于物理内存)
mem_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ -z "$mem_kib" ] || [ "$mem_kib" -le 0 ]; then
    color_echo $RED $CER "错误：无法确定内存大小。"
    exit 1
fi

# 计算内存GiB
SWAP_SIZE_GiB=$((mem_kib / 1024 / 1024))
color_echo $CYAN $CNT "检测到系统内存: ${SWAP_SIZE_GiB} GiB。交换分区将设置为此大小。"

SFDISK_INPUT=$(
    cat <<EOF
label: gpt
name=ESP, size=1G, type=U
name=swap, size=${SWAP_SIZE_GiB}G, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
name=rootfs, size=+, type=L
EOF
)

# 打印分区信息
color_echo $CYAN $CNT "即将执行分区信息如下："
color_echo $CYAN "" " - 分区表类型: gpt"
color_echo $CYAN "" " - 引导分区: 1 GiB, 类型: EFI System"
color_echo $CYAN "" " - 交换分区: ${SWAP_SIZE_GiB} GiB, 类型: Linux swap"
color_echo $CYAN "" " - 根分区: 剩余空间, 类型:  Linux filesystem"
echo

# 显示当前磁盘布局，让用户确认
color_echo $CYAN $CNT "当前磁盘 '$TARGET_DISK' 的布局："
lsblk "$TARGET_DISK"
color_echo $YELLOW $CAT "警告：这将完全擦除 '$TARGET_DISK' 上的所有数据和分区！"
read -p "你确定要继续吗？ (输入 yes 确认): " confirmation
if [ "$confirmation" != "yes" ]; then
    color_echo $RED $CER "操作已由用户中止。"
    exit 1
fi

# 使用 sfdisk 创建分区
color_echo $CYAN $CNT "正在创建分区..."
echo "$SFDISK_INPUT" | sfdisk "$TARGET_DISK" --no-reread --force

# 验证分区是否创建成功
if [ $? -ne 0 ]; then
    color_echo $RED $CER "分区创建失败"
    exit 1
fi

color_echo $GREEN $COK "分区创建成功, 当前磁盘 '$TARGET_DISK' 的布局："
fdisk -l "$TARGET_DISK"
echo

# 询问是否继续. 回车键继续
read -p "按回车键继续..."

# 判断是 SATA 还是 NVMe 磁盘
if [[ "$TARGET_DISK" =~ nvme ]]; then
    # NVMe 磁盘
    BOOT_PART="${TARGET_DISK}p1"
    SWAP_PART="${TARGET_DISK}p2"
    ROOT_PART="${TARGET_DISK}p3"
else
    # SATA 磁盘
    BOOT_PART="${TARGET_DISK}1"
    SWAP_PART="${TARGET_DISK}2"
    ROOT_PART="${TARGET_DISK}3"
fi

# 格式化分区
color_echo $CYAN $CNT "正在格式化分区..."
mkfs.fat -F32 "$BOOT_PART"
color_echo $GREEN $COK "引导分区格式化完成"

color_echo $CYAN $CNT "正在格式化交换分区..."
mkswap "$SWAP_PART"
color_echo $GREEN $COK "交换分区格式化完成"

color_echo $CYAN $CNT "正在格式化根分区..."
mkfs.btrfs -L "arch" "$ROOT_PART"
color_echo $GREEN $COK "根分区格式化完成"

# 挂载分区
color_echo $CYAN $CNT "正在挂载 Btrfs 分区..."
mount -t btrfs -o compress=zstd "$ROOT_PART" /mnt
color_echo $GREEN $COK "Btrfs 分区挂载完成"

# 创建子卷
color_echo $CYAN $CNT "正在创建子卷..."
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
color_echo $GREEN $COK "子卷创建完成"

# 卸载分区
color_echo $CYAN $CNT "正在卸载 Btrfs 分区..."
umount /mnt
color_echo $GREEN $COK "Btrfs 分区卸载完成"

# 挂载子卷
color_echo $CYAN $CNT "正在挂载子卷..."
mount -t btrfs -o compress=zstd,subvol=@ "$ROOT_PART" /mnt
mkdir -p /mnt/home
mount -t btrfs -o compress=zstd,subvol=@home "$ROOT_PART" /mnt/home
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot
swapon "$SWAP_PART"
color_echo $GREEN $COK "子卷挂载完成"
echo

# 显示当前挂载情况
df -h
echo
free -h
echo

# 询问是否继续. 回车键继续
read -p "挂载完成, 确认无误后, 按回车键继续安装基本系统..."

# 安装基本系统
color_echo $CYAN $CNT "正在安装基本系统..."
pacstrap /mnt base base-devel linux linux-firmware btrfs-progs --noconfirm
color_echo $GREEN $COK "基本系统安装完成"
echo

# 安装必要功能软件
color_echo $CYAN $CNT "正在安装必要功能软件..."
pacstrap /mnt networkmanager vim sudo zsh zsh-completions --noconfirm
color_echo $GREEN $COK "必要功能软件安装完成"
echo

# 生成 fstab 文件
color_echo $CYAN $CNT "正在生成 fstab 文件..."
genfstab -U /mnt >>/mnt/etc/fstab
color_echo $GREEN $COK "fstab 文件生成完成, 请检查"
echo

# 准备 chroot 脚本
color_echo $CYAN $CNT "正在准备 chroot 环境脚本"
cp arch-chroot-install.sh /mnt/root/
chmod +x /mnt/root/arch-chroot-install.sh

# 自动进入 chroot 环境
color_echo $CYAN $CNT "正在进入 chroot 环境并继续安装..."
arch-chroot /mnt /bin/bash -c "cd /root && bash arch-chroot-install.sh"
if [ $? -ne 0 ]; then
    color_echo $RED $CER "chroot 环境安装失败"
    exit 1
fi
color_echo $GREEN $COK "chroot 环境安装完成, 请执行以下命令完成安装"
color_echo $GREEN "" "umount -R /mnt"
color_echo $GREEN "" "reboot"
