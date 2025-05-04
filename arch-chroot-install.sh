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

# 设置主机名
color_echo $CYAN $CNT "正在设置主机名..."
read -p "请输入主机名: " hostname
if [ -z "$hostname" ]; then
    color_echo $RED $CER "主机名不能为空"
    exit 1
fi
echo "$hostname" >/etc/hostname
color_echo $GREEN $COK "主机名已设置为: $hostname"
echo

# 设置 hosts
color_echo $CYAN $CNT "正在配置 /etc/hosts 文件..."
cat <<EOF >/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF
color_echo $GREEN $COK "/etc/hosts 文件已配置完成"
echo

# 设置时区
color_echo $CYAN $CNT "正在设置时区..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
color_echo $GREEN $COK "时区设置完成"
echo

# 硬件时间设置
color_echo $CYAN $CNT "正在将系统时间同步到硬件时间..."
hwclock --systohc
color_echo $GREEN $COK "硬件时间设置完成"
echo

# 设置 nvim 别名为 vim
# color_echo $CYAN $CNT "正在设置 nvim -> vim ..."
# ln -sf /usr/bin/nvim /usr/bin/vim
# color_echo $GREEN $COK "设置 nvim -> vim 完成"
# echo

# 设置语言
color_echo $CYAN $CNT "正在设置语言..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf
color_echo $GREEN $COK "设置设置语言完成"
echo

# 设置root密码
color_echo $CYAN $CNT "正在设置 root 密码..."
read -p "请输入 root 密码" root_password
if [ -z "$root_password" ]; then
    color_echo $RED $CER "密码不能为空"
    exit 1
fi
echo -e "$root_password\n$root_password" | passwd root
if [ $? -ne 0 ]; then
    color_echo $RED $CER "设置 root 密码失败"
    exit 1
else
    color_echo $GREEN $COK "root 密码已设置"
fi
echo

# 安装微码
color_echo $CYAN $CNT "正在安装微码..."
cpu_vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
    microcode="intel"
elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
    microcode="amd"
else
    color_echo $RED $CER "未知的 CPU 类型: $cpu_vendor"
    exit 1
fi

if pacman -Qi "${microcode}-ucode" >/dev/null 2>&1; then
    color_echo $GREEN $COK "微码已安装"
else
    pacman -S --noconfirm "${microcode}-ucode"
    if [ $? -ne 0 ]; then
        color_echo $RED $CER "安装微码失败"
        exit 1
    else
        color_echo $GREEN $COK "微码安装完成"
    fi
fi
echo

# 安装引导程序
color_echo $CYAN $CNT "正在安装引导程序..."
pacman -S grub efibootmgr os-prober --noconfirm
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=5 nowatchdog"' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id='Arch Linux'
grub-mkconfig -o /boot/grub/grub.cfg
color_echo $GREEN $COK "引导程序安装完成"

# 启用网络服务
color_echo $CYAN $CNT "正在启用网络服务..."
systemctl enable NetworkManager
color_echo $GREEN $COK "启用网络服务完成"

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

# 升级全部包
color_echo $CYAN $CNT "升级系统中的全部包"
pacman -Syu
color_echo $GREEN $COK "升级完成"

# 配置 root 账户的默认编辑器
color_echo $CYAN $CNT "正在配置 root 账户的默认编辑器..."
echo "export EDITOR='vim'" >/root/.bash_profile
color_echo $GREEN $COK "root 账户的默认编辑器已配置完成"
echo

# 设置非 root 用户
color_echo $CYAN $CNT "正在设置非 root 用户..."
while true; do
    read -p "请输入非 root 用户名: " username
    if [ -z "$username" ]; then
        color_echo $RED $CER "用户名不能为空，请重新输入"
    else
        break
    fi
done
useradd -m -G wheel "$username"

while true; do
    read -p "请输入非 root 用户密码: " user_password
    if [ -z "$user_password" ]; then
        color_echo $RED $CER "密码不能为空，请重新输入"
    else
        break
    fi
done
echo -e "$user_password\n$user_password" | passwd "$username"

# 给用户设置sudo
sed -i "/^# %wheel ALL=(ALL:ALL) ALL/c\%wheel ALL=(ALL:ALL) ALL" /etc/sudoers
color_echo $GREEN $COK "已给用户 $username 设置 sudo 权限"
color_echo $GREEN $COK "非 root 用户已设置完成"
echo

# 开启 32 位支持库
color_echo $CYAN $CNT "正在开启 32 位支持库..."
sed -i 's/#\[multilib\]/\[multilib\]/' /etc/pacman.conf
sed -i 's/#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/' /etc/pacman.conf
pacman -Sy
color_echo $GREEN $COK "32 位支持库已开启"
echo

# 添加 Arch Linux CN 源
color_echo $CYAN $CNT "正在添加 Arch Linux CN 源..."
cat <<EOF >>/etc/pacman.conf
[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
EOF
pacman -Syyu
color_echo $GREEN $COK "Arch Linux CN 源已添加完成"
echo
