#!/usr/bin/env bash

Green="\033[32m"
Font="\033[0m"
Red="\033[31m"

# 检查是否为 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}错误：请使用 root 用户运行此脚本！${Font}"
        exit 1
    fi
}

# 检查虚拟化环境
check_ovz() {
    if [[ -d "/proc/vz" ]]; then
        echo -e "${Red}检测到 OpenVZ 环境，不支持创建 swap！${Font}"
        exit 1
    fi
}

# 获取根分区类型
get_root_fs() {
    df -T / | tail -1 | awk '{print $2}'
}

# 添加 SWAP
add_swap() {
    echo -e "${Green}请输入需要添加的 swap 大小（MB），建议为内存的 1~2 倍：${Font}"
    read -p "请输入 swap 数值: " swapsize

    # 检查输入是否合法
    if ! [[ "$swapsize" =~ ^[0-9]+$ ]]; then
        echo -e "${Red}输入无效！请输入整数。${Font}"
        exit 1
    fi

    # 检查是否已有 swapfile
    if grep -q "swapfile" /etc/fstab; then
        echo -e "${Red}检测到已有 swapfile，请先删除后再创建。${Font}"
        exit 1
    fi

    SWAPFILE="/swapfile"
    ROOT_FS=$(get_root_fs)
    echo -e "${Green}根分区类型: $ROOT_FS${Font}"

    echo -e "${Green}正在创建 ${swapsize}MB 的 swap 文件...${Font}"
    swapoff -a 2>/dev/null
    rm -f $SWAPFILE

    if [[ "$ROOT_FS" == "btrfs" ]]; then
        echo -e "${Green}btrfs 系统，使用 dd 创建 swap 并禁用 CoW...${Font}"
        dd if=/dev/zero of=$SWAPFILE bs=1M count=$swapsize status=progress
        chattr +C $SWAPFILE  # 禁用 CoW
        chmod 600 $SWAPFILE
        mkswap $SWAPFILE
    else
        echo -e "${Green}非 btrfs 系统，使用 fallocate 或 dd 创建 swap...${Font}"
        if ! fallocate -l "${swapsize}M" $SWAPFILE 2>/dev/null; then
            dd if=/dev/zero of=$SWAPFILE bs=1M count=$swapsize status=progress
        fi
        chmod 600 $SWAPFILE
        mkswap $SWAPFILE
    fi

    swapon $SWAPFILE

    # 设置开机自动启用
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo "$SWAPFILE none swap defaults 0 0" >> /etc/fstab
    fi

    echo -e "${Green}Swap 创建成功！当前信息：${Font}"
    swapon --show
    free -h
}

# 删除 SWAP
del_swap() {
    SWAPFILE="/swapfile"
    if grep -q "$SWAPFILE" /etc/fstab; then
        echo -e "${Green}正在删除 swap...${Font}"
        sed -i '/swapfile/d' /etc/fstab
        swapoff $SWAPFILE 2>/dev/null
        rm -f $SWAPFILE
        echo -e "${Green}Swap 已删除！${Font}"
    else
        echo -e "${Red}未检测到 swapfile，无法删除。${Font}"
    fi
}

# 主菜单
main() {
    check_root
    check_ovz
    clear
    echo -e "———————————————————————————————————————"
    echo -e "${Green}Linux VPS 一键添加/删除 SWAP（btrfs 兼容版）${Font}"
    echo -e "${Green}1.${Font} 添加 swap"
    echo -e "${Green}2.${Font} 删除 swap"
    echo -e "———————————————————————————————————————"
    read -p "请输入选项 [1-2]: " choice
    case "$choice" in
        1) add_swap ;;
        2) del_swap ;;
        *) echo -e "${Red}无效输入，请重新运行脚本！${Font}" ;;
    esac
}

main
