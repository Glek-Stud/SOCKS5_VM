#!/bin/bash

echo "Updating system"
sudo apt update && sudo apt upgrade -y
sudo apt install -y gcc make libwrap0-dev iptables-persistent wget


echo "Downloading and installing Dante"
wget https://www.inet.no/dante/files/dante-1.4.0.tar.gz
tar -xvzf dante-1.4.0.tar.gz
cd dante-1.4.0
./configure
make
sudo make install
cd ..


echo "Configuring Dante"
sudo cp /etc/sockd.conf /etc/sockd1.conf
sudo bash -c 'cat > /etc/sockd1.conf' <<EOL
logoutput: syslog

internal: eth0 port = 1081
external: eth0

socksmethod: username

user.privileged: root
user.notprivileged: nobody
user.libwrap: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
    socksmethod: username
}
EOL


INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
sudo sed -i "s/eth0/$INTERFACE/g" /etc/sockd1.conf


echo "Creating systemd  for Dante"
sudo bash -c 'cat > /etc/systemd/system/danted1.' <<EOL
[Unit]
Description=Dante SOCKS Proxy Server 1
After=network.target

[]
Type=simple
ExecStart=/usr/local/sbin/sockd -f /etc/sockd1.conf

[Install]
WantedBy=multi-user.target
EOL


echo "Enabling and starting Dante "
sudo systemctl daemon-reload
sudo systemctl enable danted1
sudo systemctl start danted1


echo "Creating proxy user"
sudo adduser --gecos "" proxyuser

read -sp "Enter password for proxyuser: " USER_PASSWORD
echo
echo "$USER_PASSWORD" | sudo passwd proxyuser --stdin

echo "Configuring firewall rules"
sudo iptables -A OUTPUT -p udp --dport 53 -d 8.8.8.8 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -d 8.8.8.8 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -d 8.8.4.4 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -d 8.8.4.4 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -j REJECT
sudo iptables -A OUTPUT -p tcp --dport 53 -j REJECT

echo "Saving firewall rules"
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6
sudo systemctl enable netfilter-persistent
sudo systemctl start netfilter-persistent

echo "Configuring DNS resolver"
sudo bash -c 'cat > /etc/resolv.conf' <<EOL
nameserver 8.8.8.8
nameserver 8.8.4.4
EOL

echo "Restarting systemd-resolved"
sudo systemctl restart systemd-resolved

echo "Restarting Dante"
sudo systemctl restart danted1

CURRENT_IP=$(curl -s ifconfig.me)

echo -e "\nSOCKS5 Proxy setup complete. Details:"
echo "-------------------------------------------"
echo "IP Address: $CURRENT_IP"
echo "Port: 1081"
echo "Username: proxyuser"
echo "Password: $USER_PASSWORD"
echo "-------------------------------------------"
