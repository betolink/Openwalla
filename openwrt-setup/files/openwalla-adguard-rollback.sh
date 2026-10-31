#!/bin/sh

# Restore dnsmasq + adblock after an AdGuard cutover.
set -eu

BACKUP="/etc/openwalla-adguard-backup"
if [ ! -f "$BACKUP/dhcp" ]; then
	echo "No AdGuard cutover backup at $BACKUP" >&2
	exit 1
fi

/etc/init.d/adguardhome stop >/dev/null 2>&1 || true
cp -p "$BACKUP/dhcp" /etc/config/dhcp
cp -p "$BACKUP/firewall" /etc/config/firewall
cp -p "$BACKUP/banip" /etc/config/banip
cp -p "$BACKUP/adblock" /etc/config/adblock
cp -p "$BACKUP/adguardhome.yaml" /etc/adguardhome/adguardhome.yaml
uci commit dhcp
uci commit firewall
uci commit banip
uci commit adblock
/etc/init.d/dnsmasq restart
/etc/init.d/adblock restart
for attempt in 1 2 3 4 5; do
	if nslookup example.com 127.0.0.1 >/dev/null 2>&1; then
		break
	fi
	sleep 1
done
echo "AdGuard rolled back; dnsmasq/adblock restored"
