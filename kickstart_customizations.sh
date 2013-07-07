#!/bin/bash


# ssd optimizations
# see https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html-single/Storage_Administration_Guide/index.html#newmds-ssdtuning
# see https://wiki.archlinux.org/index.php/SSD
# echo noop > /sys/block/sda/queue/scheduler

echo "enable AHCI in bios..."

echo "
vm.swappiness=1
vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

# echo "move /tmp to RAM in /etc/fstab?"

sed -ci 's/issue_discards\ =\ 0/issue_discards\ =\ 1/g' /etc/lvm/lvm.conf

echo "update ssd firmware: http://www.samsung.com/global/business/semiconductor/samsungssd/downloads.html"

# begin Red Hat management server registration
service messagebus start
service haldaemon start
# mkdir -p /usr/share/rhn/
wget http://ferentz.kinnick/pub/RHN-ORG-TRUSTED-SSL-CERT -O /usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT   
# rhnreg_ks --serverUrl=https://ferentz.kinnick/XMLRPC --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT --profilename=`echo $HOSTNAME` --activationkey=8d3ba2cf40c5eeae98b4b41559f045c3

# use new satellite server
cd /tmp/
wget -O - http://ferentz.kinnick/pub/bootstrap/bootstrap-base.sh | /bin/bash


###### FUNCTION SECTION ######

function configHypervisor()
{
  yum install kvm libvirt -y
    service libvirtd restart
	groupadd libvirt
	usermod -a -G kvm corey
	usermod -a -G libvirt corey
	virsh iface-bridge eth0 br0
    # http://www.howtoforge.com/how-to-install-kvm-and-libvirt-on-centos-6.2-with-bridged-networking
	cat << EOF >> /etc/sysconfig/network-scripts/ifcfg-br0
	
	EOF
	service network restart
	echo "todo: add iptables rule for bridge"
	cat << EOF >> /etc/sysctl.conf

net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
	sysctl -p /etc/sysctl.conf
	service libvirtd reload

	echo "configure lvm partitions for guest disk"
	GUESTSIZE=12GB
	for GUEST in hawkeye sanders nile ; do
		lvcreate --size ${GUESTSIZE} -n lv_vm_${GUEST} vg_fry 
		mke2fs -j -t ext4 /dev/vg_fry/lv_vm_${GUEST}
	done
	setsebool -P virt_use_sysfs 1

	echo "client instructions with virt manager"
	echo "sudo yum install virt-manager -y"
	echo "sudo virt-install --connect qemu:///system -n <GUESTNAME> -r 1024 --vcpus=2 --disk path=/dev/vg_fry/lv_vm_<GUESTNAME>,size=12 --spice --noautoconsole --os-type linux --os-variant centos6 --network=bridge:br0 --hvm --pxe"
	echo "virsh attach-device <GUESTNAME> file.xml (see https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Virtualization_Host_Configuration_and_Guest_Installation_Guide/chap-Virtualization_Host_Configuration_and_Guest_Installation_Guide-PCI_Device_Config.html)"
}

configGuest()
{
	yum install rsyslog stunnel -y
	configAll
	configLdap

	echo "configure services for secure remote logging"
	cat << stunnel_EOF > /etc/stunnel/stunnel.conf
; Client side configuration
client=yes
[ssyslog]
accept = 127.0.0.1:61514
connect = sanders.kinnick:60514
stunnel_EOF
	cat << rsyslog_EOF >> /etc/rsyslog.conf

# log everything remotely through stunnel
*.*                                                     @@127.0.0.1:61514
rsyslog_EOF

	echo "enable the stunnel service"
	groupadd -g 109 stunnel
	useradd -u 109 -g 109 -M -N -s /sbin/nlogin stunnel
	chmod 755 /etc/rc.d/init.d/stunnel
	chkconfig --add stunnel; chkconfig stunnel on
}

configAll()
{
	echo "configure sudo"
	cat << EOF >> /etc/sudoers

corey   ALL=(ALL)       NOPASSWD: ALL
EOF

	echo "disable root login via ssh"
	sed -i s/^\#PermitRootLogin.*/PermitRootLogin\ no/ /etc/ssh/sshd_config

	echo "we'd rather not use /opt"
	(umask 222 ; cat << EOF > /opt/README
Please install local applications under /usr/local instead of /opt
EOF
)

	echo "add entry for the local machine to the hosts file"
	echo "$IP_ADDRESS       $HOSTNAME $SHORTNAME" >> /etc/hosts

	echo "repair the localhost entry in the hosts file"
	sed -ci s/^127\.0\.0\.1.*/127\.0\.0\.1\ \ \ localhost.localdomain\ localhost/ /etc/hosts

	echo "disable IPv6"
	echo "alias net-pf-10 off" >> /etc/modprobe.d/noipv6.conf
	echo "options ipv6 disable=1" >> /etc/modprobe.d/noipv6.conf
	sed -ci 's/NETWORKING_IPV6.*/NETWORKING_IPV6=no/' /etc/sysconfig/network
	chkconfig ip6tables off
	sed -ci 's/inet_protocols\ =\ all/inet_protocols\ =\ ipv4/g' /etc/postfix/main.cf
}

configLdap()
{
	yum install krb5-workstation pam_krb5 openldap-clients nss-pam-ldapd sssd -y

	echo "configure system authentication and authorization for Active Directory"
	authconfig  --useshadow  --enablemd5  --enablecache --enablekrb5 --krb5realm=KINNICK --enablekrb5kdcdns --enablekrb5realmdns --enablemkhomedir --enablelocauthorize --enableldap --ldapserver=ldap.kinnick --ldapbasedn="dc=kinnick" --disablesmartcard --disablefingerprint --update

	echo "set proper directory permissions for home directory creation in /etc/pam.d/system-auth"
	sed -ci '/pam_mkhomedir.so/s/$/\ umask\=077/' /etc/pam.d/system-auth-ac
	
	echo "TODO: configure sssd"
}

###### END FUNCTION SECTION ######


# If this is a VM, install virtio paravirtualization tools from the configured repo
# http://wiki.libvirt.org/page/Virtio


# guest server customizations
case `echo $(hostname -s)` in
    hawkeye)
		echo "detected nfs/samba server with bulk storage pci passthrough"
		configureGuest
		;;
	sanders)
		echo "detected centralized rsyslog and reporting server"
		echo "todo: rsyslog and reporting server config"
		configureGuest
		;;
	nile)
		echo "detected open ldap server"
		echo "todo: openldap server config"
		configureGuest
		;;
	dwight)
		echo "detected home theater pc (htpc) and dlna server"
		echo "TODO: dlna server config; nfs mounts to media"
		configureGuest
	fry)
		echo "detected hypervisor install"
		configureHypervisor
		;;
esac
