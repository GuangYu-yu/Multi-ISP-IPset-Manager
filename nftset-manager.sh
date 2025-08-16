#!/bin/bash

# 创建配置目录
mkdir -p /etc/nftables_configs

# 写入 vars.sh 脚本
cat << 'EOF' > /etc/nftables_configs/vars.sh
#!/bin/bash

CFG_DIR="/etc/nftables_configs"

validate_input() {
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "无效的名称"; exit 1
    fi
    if [[ "$url" != "" && ! "$url" =~ ^https?:// ]]; then
        echo "无效的URL"; exit 1
    fi
    if [ "$type" != "4" ] && [ "$type" != "6" ]; then
        echo "无效的类型"; exit 1
    fi
}

download_file() {
    local retries=3
    local count=0
    while [ $count -lt $retries ]; do
        wget -qO $1 $2
        if [ -s $1 ]; then
            return 0
        fi
        count=$((count + 1))
        sleep 1
    done
    return 1
}

add_nftables_set() {
    validate_input
    # 根据IP类型确定地址族：IPv4使用ip，IPv6使用ip6
    family="ip$( [ "$type" -eq 6 ] && echo "6")"
    f=$CFG_DIR/${name}.txt
    rm -f $f
    if ! download_file $f $url; then echo "下载失败或文件为空"; exit 1; fi
    # 创建nftables表（如果不存在）
    nft add table $family filter 2>/dev/null || true
    # 删除已存在的同名集合（避免属性冲突）
    nft delete set $family filter $name 2>/dev/null || true
    # 创建新的IP地址集合，支持网络段和自动合并
    nft add set $family filter $name { type ${family}_addr\; flags interval\; auto-merge\; }
    # 清空集合内容
    nft flush set $family filter $name
    # 逐行添加IP地址到集合中
    while read -r line; do
        [ -n "$line" ] && nft add element $family filter $name { $line }
    done < $f
    # 更新配置列表：先删除旧记录，再添加新记录
    grep -v "^$name " $CFG_DIR/nftables_list > /tmp/nftables_list
    mv /tmp/nftables_list $CFG_DIR/nftables_list
    echo "$name $url $type" >> $CFG_DIR/nftables_list
}

clear_and_update_nftables_set() {
    f=$CFG_DIR/${name}.txt
    > $f
    # 从配置列表中读取URL和类型信息
    read url type < <(grep "^$name " $CFG_DIR/nftables_list | awk "{print \$2, \$3}")
    if [ -z "$url" ] || [ -z "$type" ]; then
        echo "未找到 URL 或 类型"
        exit 1
    fi
    validate_input
    if ! download_file $f $url; then
        echo "下载失败或文件为空"
        exit 1
    fi
    # 根据IP类型确定地址族
    family="ip$( [ "$type" -eq 6 ] && echo "6")"
    # 清空现有集合内容
    nft flush set $family filter $name
    # 重新添加下载的IP地址到集合
    while read -r line; do
        [ -n "$line" ] && nft add element $family filter $name { $line }
    done < $f
}
EOF

# 清空 nftables 列表文件
> /etc/nftables_configs/nftables_list

# 写入 init 启动脚本
cat << 'EOF' > /etc/init.d/nftables_load
#!/bin/bash /etc/rc.common

START=99
start() {
    # 加载配置变量和函数
    . /etc/nftables_configs/vars.sh
    # 遍历配置列表中的每个集合
    while IFS=" " read -r name url type; do
        # 根据IP类型确定地址族
        family="ip$( [ "$type" -eq 6 ] && echo "6")"
        f=$CFG_DIR/${name}.txt
        # 如果IP地址文件存在，则加载到nftables
        if [ -f $f ]; then
            # 创建nftables表
            nft add table $family filter 2>/dev/null
            # 创建IP地址集合
            nft add set $family filter $name { type ${family}_addr\; flags interval\; auto-merge\; } 2>/dev/null
            # 清空集合内容
            nft flush set $family filter $name
            # 逐行添加IP地址到集合
            while read -r line; do
                [ -n "$line" ] && nft add element $family filter $name { $line } 2>/dev/null
            done < $f
        fi
    done < $CFG_DIR/nftables_list
}
EOF

# 赋予执行权限
chmod +x /etc/init.d/nftables_load

# 设置开机启动
/etc/init.d/nftables_load enable