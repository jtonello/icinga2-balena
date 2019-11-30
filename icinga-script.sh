#!/bin/bash
username="jtonello"

# Scan the network and create a file of active IP addresses
sudo arp-scan 10.128.1.0/24 | grep -oP '^[\d.]+' > /usr/src/app/network-hosts

# Remove the trailing '30' in the hosts file
sed -i '$d' /usr/src/app/network-hosts

# Remove duplicate IPs
cat network-hosts | sort -u > /usr/src/app/network-hosts-depupe
mv network-hosts-depupe /usr/src/app/network-hosts

# Create an array for hosts that should only be pinged (no services)
declare -a no_ssh
no_ssh=(10.128.1.1 10.128.1.4 10.128.1.9)

# Remove the routers above from the network-hosts file
for i in "${no_ssh[@]}"
do
        sed -i "/$i$/d" /usr/src/app/network-hosts
done

# Add the router.tiny.lab entry, which will become the parent
echo 'object Host NodeName {
        import "generic-host"
        address = "10.128.1.209"
        vars.os = "Linux"
        vars.http_vhosts["http"] = {
          http_uri = "/icingaweb2"
          http_port = "80"
        }
        vars.disks["disk /"] = {
          disk_partitions = "/"
        }
        vars.notification["mail"] = {
          groups = [ "icingaadmins" ]
        }
}
' > hosts.conf

# Get the hostnames of each host on the network
#echo "Enter password for username on each system..."
sshpass -f remotePasswordFile parallel-ssh -i -h network-hosts -l $username -A -P "hostname && hostname -i" < /usr/src/app/remotePasswordFile > /usr/src/app/hostname.txt
#pssh -i -h network-hosts -Aq -l $username cat /etc/hostname > hostname.txt

sed -i '/^\[.*$/d' /usr/src/app/hostname.txt
sed -ni '/^.*: [a-z]/p' /usr/src/app/hostname.txt
sed -nEi "{s/(^.*): (.*$)/\2\t\1/;p}" /usr/src/app/hostname.txt
sed -i '/^do not.*/d' /usr/src/app/hostname.txt
sed -i '/^Connection refused.*/d' /usr/src/app/hostname.txt
sed -i '/^Name or.*/d' /usr/src/app/hostname.txt
sed -i '/^No route.*/d' /usr/src/app/hostname.txt

# Create host.cfg and service.cfg entries for each host
while read hostn; do
        ip=$(sed -nE "s/^$hostn.*\t(.*$)/\1/p" /usr/src/app/hostname.txt)
        hosts=("object Host \"$hostn\" {\n
                \timport \"generic-host\"\n
                \tvars.os = \"Linux\"\n
                \taddress = \"$ip\"\n
                }\n")

       # hosts=("${hosts}\t}\n")

        echo -e $hosts >> /usr/src/app/hosts.conf
done < <(sed -nE "{s/(^.*)\t(.*$)/\1/;p}" /usr/src/app/hostname.txt)

# Remove duplicate IPs in object entries
sed -nEi "{s/(^.*)(10\.128.*) .*$/\1\2\"/;p}" /usr/src/app/hosts.conf
sed -nEi "{s/(^.*)(10\.128.*) .*$/\1\2\"/;p}" /usr/src/app/hosts.conf

# Copy the cfg files to the nagios root
cp /usr/src/app/hosts.conf /etc/icinga2/conf.d/

# Restart Nagios
service icinga2 reload

