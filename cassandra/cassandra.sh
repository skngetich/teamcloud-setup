#!/bin/bash

sysctl_conf="/etc/sysctl.conf"

# Check if sysctl.conf exists
if [ -f "$sysctl_conf" ]; then
    sysctl -w \
        net.ipv4.tcp_keepalive_time=60 \
        net.ipv4.tcp_keepalive_probes=3 \
        net.ipv4.tcp_keepalive_intvl=10
   
    # Apply the changes
    sysctl -p
    echo "TCP keepalive timeout values set successfully"


    sysctl -w \
        net.core.rmem_max=16777216 \
        net.core.wmem_max=16777216 \
        net.core.rmem_default=16777216 \
        net.core.wmem_default=16777216 \
        net.core.optmem_max=40960 \
        net.ipv4.tcp_rmem='4096 87380 16777216' \
        net.ipv4.tcp_wmem='4096 65536 16777216'
    # Apply the changes
    sysctl -p
    echo "System can now handle thousands of concurrent connections used by the database"

else
    echo "Error: $sysctl_conf not found."
    exit 1
fi
