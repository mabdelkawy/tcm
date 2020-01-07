#! /bin/bash

# ip tables rules enabling sharing
# enp1s0 or wlp2s0 is the interface connected to router (WAN)
# enp1s1 is the interface connected to local network (LAN)



echo "sudo -u root /home/..../Desktop/TCM.sh"
echo "Connect the two interfaces of the server before running script make sure ethernet and wifi is active and connected"
echo "Started"
modprobe ip_tables  
modprobe ip_conntrack
modprobe ip_conntrack_irc
modprobe ip_conntrack_ftp
modprobe act_mirred
modprobe sch_fq_codel
modprobe ifb
i=0

ip link set dev ifb0 up

nmcli connection show

INGRESS_INTERFACE="ifb0"
LAN_CONNECTION_NAME="LAN1"
WAN_CONNECTION_NAME="WAN1"

# Get default connection names NOT SSID or Interface names

read -p "Write LAN connection name:" LAN_DEFAULT_CONNECTION_NAME
read -p "Write WAN connection name:" WAN_DEFAULT_CONNECTION_NAME


read -p "Choose method for connection type from:[shared|gateway]: " METHOD

until [[ "$METHOD" == "shared" || "$METHOD" == "gateway" ]] ;do
read -p "Enter:[shared|gateway]" METHOD
done

# Modify netowrk names to easy minipulate

nmcli con mod "`echo $LAN_DEFAULT_CONNECTION_NAME`" connection.id $LAN_CONNECTION_NAME #LAN1
nmcli con mod "`echo $WAN_DEFAULT_CONNECTION_NAME`" connection.id $WAN_CONNECTION_NAME #WAN1


# Getting networks interfaces names from system

WAN_INTERFACE="$(nmcli con show $WAN_CONNECTION_NAME| awk '/GENERAL.DEVICES/ {print $2}')"
LAN_INTERFACE="$(nmcli con show $LAN_CONNECTION_NAME| awk '/GENERAL.DEVICES/ {print $2}')"

# Getting networks interfaces LAN IP range from system

LOCAL_WAN_NETOWRK="$(nmcli con show $WAN_CONNECTION_NAME| awk '/IP4.ADDRESS/ {print $2}')"
LOCAL_LAN_NETWORK="$(nmcli con show $LAN_CONNECTION_NAME | awk '/IP4.ADDRESS/ {print $2}')"

echo "WIFI as acess point sub-LAN network should configured inside parent LAN"

# Establishing ip4 shared interface or a gateway

if [[ "$METHOD" == "shared" ]]; then
nmcli con mod $LAN_CONNECTION_NAME ipv4.method shared #LAN1 shared
elif [[ "$METHOD" == "gateway" ]]; then #LAN1 gateway
nmcli con mod $LAN_CONNECTION_NAME ipv4.addresses $LOCAL_LAN_NETWORK 
nmcli con mod $LAN_CONNECTION_NAME ipv4.gateway ${LOCAL_LAN_NETWORK::-3} 
nmcli con mod $LAN_CONNECTION_NAME ipv4.method manual
nmcli con up $LAN_CONNECTION_NAME
fi

# establish iptables for LAN

echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -F POSTROUTING
iptables -t nat -A POSTROUTING -o $WAN_INTERFACE -j MASQUERADE
iptables -A FORWARD -i $WAN_INTERFACE -o $LAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $LAN_INTERFACE -o $WAN_INTERFACE -j ACCEPT

# LAN Forwarding

iptables -A FORWARD -i $LAN_INTERFACE -j ACCEPT
iptables -A FORWARD -o $LAN_INTERFACE -j ACCEPT

COMMAND="N/A"

while [ "$COMMAND" != "end" ]; do

start() {

# Extract default parameters of network interfaces

WAN_TXQUEUELEN=$(ifconfig $WAN_INTERFACE | awk '/txqueuelen/ {print $2}' | sed 's/[^0-9]//g')
echo "WAN Txqueuelen=$WAN_TXQUEUELEN"
LAN_TXQUEUELEN=$(ifconfig $LAN_INTERFACE | awk '/txqueuelen/ {print $2}' | sed 's/[^0-9]//g')
echo "LAN Txqueuelen=$LAN_TXQUEUELEN"
IBF_TXQUEUELEN=$(ifconfig $INGRESS_INTERFACE | awk '/txqueuelen/ {print $2}' | sed 's/[^0-9]//g')
echo "IBF Txqueuelen=$IBF_TXQUEUELEN"
WAN_MTU=$(ifconfig $WAN_INTERFACE | awk '/MTU/ {print $5}' | sed 's/[^0-9]//g')
echo "WAN MTU=$WAN_MTU"
LAN_MTU=$(ifconfig $LAN_INTERFACE | awk '/MTU/ {print $5}' | sed 's/[^0-9]//g')
echo "LAN MTU=$LAN_MTU"
IBF_MTU=$(ifconfig $INGRESS_INTERFACE | awk '/MTU/ {print $5}' | sed 's/[^0-9]//g')
echo "IBF MTU=$IBF_MTU"

read -p "Maximum Download limit (mbit)=" MAXDOWN #mbit
DOWNPERCENT=0.96
read -p "Maximum upload limit (mbit)=" MAXUP #mbit
UPPERCENT=0.96 
read -p "Set total minimum time delay (second)=" MINTIME #Second
read -p "Set total maximum time delay (second)=" MAXTIME #Second


echo "Default PC number in ethernet local network:20"
echo "Default PC number in wifi local network:40"
echo "To add additional PCs, just enter the number of PCs want to add"
read -p "Additional PC number=" ADD_PCNUM

FROM_PORT=1
TO_PORT=$PRIORITY_LEVELS
PORT_CLASSID="seq $FROM_PORT $TO_PORT"

FROM_LAN=10 
TO_LAN=$((ADD_PCNUM+20))
PCNUM_LAN=$((TO_LAN-FROM_LAN))
CLASSID_LAN="seq $FROM_LAN $TO_LAN"

WIFI_CLASSID=$((TO_LAN+1))

FROM_WIFI=$((WIFI_CLASSID+1))
TO_WIFI=$((WIFI_CLASSID+40))
PCNUM_WIFI=$((TO_WIFI-FROM_WIFI))
CLASSID_WIFI="seq $FROM_WIFI $TO_WIFI"


# Accept fraction through python code

NEAR_MAX_DOWNRATE=$(python -c "print ($MAXDOWN*$DOWNPERCENT)*1000")
MAXDOWN_DIVIDE_PCNUM_LAN=$(python -c "print ($NEAR_MAX_DOWNRATE/$PCNUM_LAN)*1000")
MAXDOWN_DIVIDE_PCNUM_WIFI=$(python -c "print ($NEAR_MAX_DOWNRATE/$PCNUM_WIFI)*1000")

# *1000 Convert to kbit

NEAR_MAX_DOWNRATE=`echo "${NEAR_MAX_DOWNRATE%\.*}"`
MAXDOWN_DIVIDE_PCNUM_LAN=`echo "${MAXDOWN_DIVIDE_PCNUM_LAN%\.*}"`
MAXDOWN_DIVIDE_PCNUM_WIFI=`echo "${MAXDOWN_DIVIDE_PCNUM_WIFI%\.*}"`

NEAR_MAX_UPRATE=$(python -c "print ($MAXUP*$UPPERCENT)*1000")
MAXUP_DIVIDE_PCNUM_LAN=$(python -c "print ($NEAR_MAX_UPRATE/$PCNUM_LAN)*1000") 
MAXUP_DIVIDE_PCNUM_WIFI=$(python -c "print ($NEAR_MAX_UPRATE/$PCNUM_WIFI)*1000") 

# Integar only

NEAR_MAX_UPRATE=`echo "${NEAR_MAX_UPRATE%\.*}"`
MAXUP_DIVIDEPCNUM_LAN=`echo "${MAXUP_DIVIDE_PCNUM_LAN%\.*}"`
MAXUP_DIVIDEPCNUM_WIFI=`echo "${MAXUP_DIVIDE_PCNUM_WIFI%\.*}"`



# fq_codel shaping algorithm parameters

read -p "(Recommanded Overhead MTU=1) Overhead maximum size packet (MTU)=" OVERHEAD

LIMIT_LANDOWN=$((NEAR_MAX_DOWNRATE/(LAN_MTU/8)))
LIMIT_LANUP=$((NEAR_MAX_UPRATE/(LAN_MTU/8)))
LIMIT_WIFIDOWN=$((NEAR_MAX_DOWNRATE/(LAN_MTU/8)))
LIMIT_WIFIUP=$((NEAR_MAX_UPRATE/(LAN_MTU/8)))

TARGET_LANDOWN=$((MINTIME*LIMIT_LANDOWN))
TARGET_LANUP=$((MINTIME*LIMIT_LANUP))
TARGET_WIFIDOWN=$((MINTIME*WIFIDOWN))
TARGET_WIFIUP=$((MINTIME*WIFIUP))

INTERVAL_LANDOWN=$((MAXTIME*LIMIT_LANDOWN))
INTERVAL_LANUP=$((MAXTIME*LIMIT_LANUP))
INTERVAL_WIFIDOWN=$((MAXTIME*WIFIDOWN))
INTERVAL_WIFIUP=$((MAXTIME*WIFIUP))

read -p "Linklayer at begining of shaping {adsl | atm | ethernet) Linklayer=" LINKLAYER_HTB
read -p "Linklayer at end of shaping {adsl | atm | ethernet) Linklayer=" LINKLAYER_FQCODEL
read -p "Quantum at begining of shaping default=default MTU=1500 Quantum=" QUANTUM_HTB
read -p "Quantum at end of shaping recommanded=300 , default=default MTU=1500 Quantum=" QUANTUM_FQCODEL



################################################################################################################################################
################################################################################################################################################
                                                  #MAIN CODE THAT DOES TRAFFIC SHAPPING
################################################################################################################################################
################################################################################################################################################

h=-1

#INGRESS
# Limit download LAN

tc qdisc add dev ${WAN_INTERFACE} handle ffff: ingress

ifconfig ${INGRESS_INTERFACE} up 

# Redirect from ingress WAN to IFB
tc filter add dev ${WAN_INTERFACE} parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev ${INGRESS_INTERFACE}

# Create an EGRESS filter on the IFB device (Act like egress but practically ingress) ( HTB DEFAULT: UNFILTERED TRAFFIC GOES TO WIFI CLASSID )
tc qdisc add dev ${INGRESS_INTERFACE} root handle 1:0 stab overhead ${OVERHEAD} linklayer ${LINKLAYER_HTB} quantum ${QUANTUM_HTB} htb default ${WIFI_CLASSID}
tc class add dev ${INGRESS_INTERFACE} parent 1:0 classid 1:1 htb rate ${NEAR_MAX_DOWNRATE}kbit ceil ${NEAR_MAX_DOWNRATE}kbit

       for i in `$CLASSID_LAN`;
        do
        tc class add dev ${INGRESS_INTERFACE} parent 1:1 classid 1:${i} htb rate ${MAXDOWN_DIVIDE_PCNUM_LAN}kbit ceil ${NEAR_MAX_DOWNRATE}kbit
        h=$((h+1))
        tc filter add dev ${INGRESS_INTERFACE} protocol ip parent 1:0 prio 1 u32 match ip dst `echo $LOCAL_LAN_NETWORK | sed s/./${h}/$((${#LOCAL_LAN_NETWORK}-3))` flowid 1:${i}
        tc qdisc add dev ${INGRESS_INTERFACE} parent 1:${i} handle ${i}:0 stab overhead ${OVERHEAD} linklayer ${LINKLAYER_FQCODEL} fq_codel limit ${LIMIT_LANDOWN} target ${TARGET_LANDOWN} interval ${INTERVAL_LANDOWN} quantum ${QUANTUM_FQCODEL} ecn 

        done
		
# h counting continue

# Limit download WIFI under LAN

tc class add dev ${INGRESS_INTERFACE} parent 1:1 classid 1:${WIFI_CLASSID} htb rate ${MAXDOWN_DIVIDE_PCNUM_LAN}kbit ceil ${NEAR_MAX_DOWNRATE}kbit

        for i in `$CLASSID_WIFI`;
        do
        tc class add dev ${INGRESS_INTERFACE} parent 1:${WIFI_CLASSID} classid 1:${i} htb rate ${MAXDOWN_DIVIDE_PCNUM_WIFI}kbit ceil ${NEAR_MAX_DOWNRATE}kbit
        h=$((h+1))
        tc filter add dev ${INGRESS_INTERFACE} protocol ip parent 1:0 prio 1 u32 match ip dst `echo $LOCAL_LAN_NETWORK | sed s/./${h}/$((${#LOCAL_LAN_NETWORK}-3))` flowid 1:${i}
        tc qdisc add dev ${INGRESS_INTERFACE} parent 1:${i} handle ${i}:0 stab overhead ${OVERHEAD} linklayer ${LINKLAYER_FQCODEL} fq_codel limit ${LIMIT_WIFIDOWN} target ${TARGET_WIFIDOWN} interval ${INTERVAL_WIFIDOWN} quantum ${QUANTUM_FQCODEL} ecn 
        done
h=-1

#EGRESS
# Limit upload LAN
#( HTB DEFAULT: UNFILTERED TRAFFIC GOES TO WIFI CLASSID )
tc qdisc add dev ${LAN_INTERFACE} root handle 1:0 stab overhead ${OVERHEAD} linklayer ${LINKLAYER_HTB} quantum ${QUANTUM_HTB} htb default ${WIFI_CLASSID}

        for i in `$CLASSID_LAN`;
        do
        tc class add dev ${LAN_INTERFACE} parent 1:1 classid 1:${i} htb rate ${MAXUP_DIVIDE_PCNUM_LAN}kbit ceil ${NEAR_MAX_UPRATE}kbit
        h=$((h+1))
        tc filter add dev ${LAN_INTERFACE} protocol ip parent 1:0 prio 1 u32 match ip src `echo $LOCAL_LAN_NETWORK | sed s/./${h}/$((${#LOCAL_LAN_NETWORK}-3))` flowid 1:${i}
        tc qdisc add dev ${LAN_INTERFACE} parent 1:${i} handle ${i}:0 stab overhead ${OVERHEAD} linklayer ${LINKLAYER_FQCODEL} fq_codel limit ${LIMIT_LANUP} target ${TARGET_LANUP} interval ${INTERVAL_LANUP} quantum ${QUANTUM_FQCODEL} ecn 

        done
   


# h will continue
# Limit upload WIFI under LAN

tc class add dev ${LAN_INTERFACE} parent 1:0 classid 1:1 htb rate ${NEAR_MAX_UPRATE}kbit ceil ${NEAR_MAX_UPRATE}kbit
tc class add dev ${LAN_INTERFACE} parent 1:1 classid 1:${WIFI_CLASSID} htb rate ${MAXUP_DIVIDE_PCNUM_LAN}kbit ceil ${NEAR_MAX_UPRATE}kbit

        for i in `$CLASSID_WIFI`;
        do
        tc class add dev ${LAN_INTERFACE} parent 1:${WIFI_CLASSID} classid 1:${i} htb rate ${MAXDUP_DIVIDE_PCNUM_WIFI}kbit ceil ${NEAR_MAX_UPRATE}kbit
        h=$((h+1))
        tc filter add dev ${LAN_INTERFACE} protocol ip parent 1:0 prio 1 u32 match ip src `echo $LOCAL_LAN_NETWORK | sed s/./${h}/$((${#LOCAL_LAN_NETWORK}-3))` flowid 1:${i}
        tc qdisc add dev ${LAN_INTERFACE} parent 1:${i} handle ${i}:0 stab overhead ${OVERHEAD} linklayer ${LINKLAYER_FQCODEL} fq_codel limit ${LIMIT_WIFIUP} target ${TARGET_WIFIUP} interval ${INTERVAL_WIFIUP} quantum ${QUANTUM_FQCODEL} ecn 

        done

h=-1


################################################################################################################################################
################################################################################################################################################
################################################################################################################################################
################################################################################################################################################


# Restart Netowrk Manager
systemctl restart network-manager


}

manual(){

    # Manual configuration of interfaces paramters (Txqueuelen and MTU)

    read -p "LAN Txqueuelen=" LANTXQUEUELEN
    ifconfig ${LAN_INTERFACE} txqueuelen ${LANTXQUEUELEN}
    read -p "WAN Txqueuelen=" WANTXQUEUELEN
    ifconfig ${WAN_INTERFACE} txqueuelen ${WANTXQUEUELEN}
    read -p "IBF Txqueuelen=" IBFTXQUEUELEN
    ifconfig ${INGRESS_INTERFACE} txqueuelen ${IBFTXQUEUELEN}

    read -p "LAN MTU=" LANMTU
    ifconfig ${LAN_INTERFACE} mtu ${LANMTU}
    read -p "WAN MTU=" WANMTU
    ifconfig ${WAN_INTERFACE} mtu ${WANMTU}
    read -p "IBF MTU=" LANMTU
    ifconfig ${INGRESS_INTERFACE} mtu ${IBFMTU}

    start
    


}

stop() {

    # remove any existing qdiscs
    tc qdisc del dev $INGRESS_INTERFACE root 2> /dev/null
    tc qdisc del dev $INGRESS_INTERFACE ingress 2> /dev/null
    tc qdisc del dev $LAN_INTERFACE root 2> /dev/null
    tc qdisc del dev $LAN_INTERFACE ingress 2> /dev/null
     
    # Flush and delete tables
    iptables -t mangle --delete POSTROUTING -o WAN_INTERFACE -j SHAPER 2> /dev/null
    iptables -t mangle --flush SHAPER 2> /dev/null
    iptables -t mangle --delete-chain SHAPER 2> /dev/null
    
    # Return Default values of interfaces
    ifconfig ${LAN_INTERFACE} txqueuelen 1000
    ifconfig ${WAN_INTERFACE} txqueuelen 1000
    ifconfig ${INGRESS_INTERFACE} txqueuelen 32

    ifconfig ${LAN_INTERFACE} mtu 1500
    ifconfig ${WAN_INTERFACE} mtu 1500
    ifconfig ${INGRESS_INTERFACE} mtu 1500

    echo "Shaping stoped and flushed"
    echo "Done"


}

restart() {

    stop
    sleep 1
    start

}

show() {

    # Display status of traffic control status.
    tc -g -s class show dev $INGRESS_INTERFACE
    tc -g -s class show dev $LAN_INTERFACE
    tc -s qdisc ls dev $INGRESS_INTERFACE
    tc -s qdisc ls dev $LAN_INTERFACE
    iptables -t mangle -n -v -L
    echo "Done"

}

case $COMMAND in

    start)

        echo -n "Starting bandwidth shaping: "
        start
        echo "Done"
        ;;

    stop)

        echo -n "Stopping bandwidth shaping: "
        stop
        echo "Done"
        ;;

    restart)

        echo -n "Restarting bandwidth shaping: "
        restart
        echo "Done"
        ;;

    show)

        echo "Bandwidth shaping status for $INGRESS_INTERFACE,$LAN_INTERFACE:"
        show
        echo "Done"
        ;;

    manual)

        echo "Advanced user manual configuration: "
        manual
        echo "Done"
        ;;

    *)
        if [ "$COMMAND" != "N/A" ];
        then
        echo "ERROR:Please enter exactly matching parameter from:[start|stop|restart|manual|show|end]"
        else
        echo -e "Blank text not allowed \nExit by entering: end \nInner paramter values manual configuration by entering: manual \nplease enter a parameter from:[start|stop|restart|manual|show|end]"
        fi
        ;;

esac
read -p "Enter[start|stop|restart||manual|show|end]:" COMMAND
done
exit 0
