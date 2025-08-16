#!/bin/bash

# 创建配置目录
mkdir -p /etc/ipset_configs

# 写入 vars.sh 脚本
cat << 'EOF' > /etc/ipset_configs/vars.sh
#!/bin/sh

CFG_DIR="/etc/ipset_configs"

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

add_ipset() {
    validate_input
    family="inet$( [ "$type" -eq 6 ] && echo "6")"
    f=$CFG_DIR/${name}.txt
    rm -f $f
    if ! download_file $f $url; then echo "下载失败或文件为空"; exit 1; fi
    ipset create $name hash:net family $family -exist
    ipset flush $name
    sed -e "s/^/add $name /" $f | ipset restore -!
    grep -v "^$name " $CFG_DIR/ipset_list > /tmp/ipset_list
    mv /tmp/ipset_list $CFG_DIR/ipset_list
    echo "$name $url $type" >> $CFG_DIR/ipset_list
}

clear_and_update_ipset() {
    f=$CFG_DIR/${name}.txt
    > $f
    read url type < <(grep "^$name " $CFG_DIR/ipset_list | awk "{print \$2, \$3}")
    if [ -z "$url" ] || [ -z "$type" ]; then
        echo "未找到 URL 或 类型"
        exit 1
    fi
    validate_input
    if ! download_file $f $url; then
        echo "下载失败或文件为空"
        exit 1
    fi
    ipset flush $name
    sed -e "s/^/add $name /" $f | ipset restore -!
}
EOF

# 清空 ipset 列表文件
> /etc/ipset_configs/ipset_list

# 写入 init 启动脚本
cat << 'EOF' > /etc/init.d/ipset_load
#!/bin/sh /etc/rc.common

START=99
start() {
    . /etc/ipset_configs/vars.sh
    while IFS=" " read -r name url type; do
        family="inet$( [ "$type" -eq 6 ] && echo "6")"
        f=$CFG_DIR/${name}.txt
        [ -f $f ] && ipset create $name hash:net family $family -exist && ipset flush $name && sed -e "s/^/add $name /" $f | ipset restore -!
    done < $CFG_DIR/ipset_list
}
EOF

# 赋予执行权限
chmod +x /etc/init.d/ipset_load

# 设置开机启动
/etc/init.d/ipset_load enable