#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Variables 
ipt="$(which iptables)"
ipt_save_v4="/etc/iptables/rules.v4"
ipt_save_v6="/etc/iptables/rules.v6"
if_lan=""
if_wan="ens192"
trusted="213.147.0.0/19"
default_policy="DROP"
new_tcp_in="-p tcp -m state --state NEW -m tcp --dport"

get_args() {

        while [[ "$1" ]] ; do

                case $1 in

                        -a|--accept)    default_policy="ACCEPT"         ;;
                        -d|--drop)      default_policy="DROP"           ;;
                        -r|--reject)    default_policy="REJECT"         ;;
                        -x|--debug)     set -o xtrace                   ;;
                        -l|--lan)       if_lan="${2:-error}" ; shift    ;;
                        -w|--wan)       if_wan="${2:-error}" ; shift    ;;
                        -S|--ssh-only)  ssh_only="true"                 ;;
                        *)              echo "$1: option not recognized";;
                esac
                shift
        done
}

start() {

	# Delete everything
	$ipt -F
	$ipt -X
	
	# DEFAULT CHAIN POLICIES
	$ipt -P INPUT "${default_policy:-ACCEPT}"
	$ipt -P OUTPUT ACCEPT # "${default_policy:-ACCEPT}"
	$ipt -P FORWARD "${default_policy:-ACCEPT}"

	# LOOPBACK
	$ipt -A INPUT -i lo -j ACCEPT
	$ipt -A OUTPUT -o lo -j ACCEPT

	$ipt -N LOG_DROP	# Logging of especially invalid packets
	$ipt -N LOG_ACCEPT	# Log but accept

	# PREROUTING 
	$ipt -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP
	$ipt -t mangle -A PREROUTING -p tcp ! --syn -m state --state NEW -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags ALL FIN,URG,PSH -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags ALL SYN,FIN,RST,PSH,URG -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags SYN,FIN,PSH SYN,FIN,PSH -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags SYN,FIN,URG SYN,FIN,URG -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags SYN,FIN,RST SYN,FIN,RST -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags ALL ALL -j LOG_DROP
	$ipt -t mangle -A PREROUTING -p tcp --tcp-flags ALL NONE -j LOG_DROP


# BASIC INPUT RULES
	
  	# Drop new connections not starting with a SYN packet
	$ipt -A INPUT -p tcp ! --syn -m state --state NEW -j LOG_DROP

	# Syn-flood protection
	$ipt -A INPUT -p tcp --syn -m state --state NEW -m limit --limit 1/s -j ACCEPT

	# Fragmentet packets
	$ipt -t mangle -A PREROUTING -f -j DROP

	# Drop Invalid TCP-Flag combinations
	$ipt -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags ALL SYN,FIN,RST,PSH,URG -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags SYN,FIN,PSH SYN,FIN,PSH -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags SYN,FIN,URG SYN,FIN,URG -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags SYN,FIN,RST SYN,FIN,RST -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags ALL ALL -j LOG_DROP
	$ipt -A INPUT -p tcp --tcp-flags ALL NONE -j LOG_DROP


  	# Allow already established connections 
	$ipt -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 

	# LOG and BLOCK  unnecessary packets
	if [[ ! -z "${if_wan}" ]] ; then 
	
		# BLOCK RFC1918 WAN - PRIVATE NET
		$ipt -A INPUT -i "${if_wan}" -s 10.0.0.0/8 -j LOG_DROP
		$ipt -A INPUT -i "${if_wan}" -s 172.16.0.0/12 -j LOG_DROP
		$ipt -A INPUT -i "${if_wan}" -s 192.168.0.0/16 -j LOG_DROP
		# BLOCK RFC 3927 WAN - LINK-LOCAL
		$ipt -A INPUT -i "${if_wan}" -s 169.254.0.0/16 -j LOG_DROP
		# BLOCK RFC 3171 WAN - MULTICAST
		$ipt -A INPUT -i "${if_wan}" -s 224.0.0.0/4 -j LOG_DROP
		# BLOCK RFC 1700 WAN - RESERVED
		$ipt -A INPUT -i "${if_wan}" -s 240.0.0.0/4 -j LOG_DROP
		# BLOCK RFC6890 WAN - IETF PA/TEST
		$ipt -A INPUT -i "${if_wan}" -s 0.0.0.0/8 -j LOG_DROP
		$ipt -A INPUT -i "${if_wan}" -s 192.0.0.0/24 -j LOG_DROP
		$ipt -A INPUT -i "${if_wan}" -s 192.0.2.0/24 -j LOG_DROP
		$ipt -A INPUT -i "${if_wan}" -s 198.51.100.0/24 -j LOG_DROP
		$ipt -A INPUT -i "${if_wan}" -s 203.0.113.0/24 -j LOG_DROP
		# BLOCK RFC6598 - Shared Address Space
		$ipt -A INPUT -i "${if_wan}" -s 100.64.0.0/10 -j LOG_DROP
		# BLOCK RFC2544 - Benchmarking
		$ipt -A INPUT -i "${if_wan}" -s 198.18.0.0/15 -j LOG_DROP

	fi
	
	$ipt -A LOG_DROP -m limit --limit 1/s -j LOG --log-prefix 'Iptables DROP : ' --log-level 7
	$ipt -A LOG_DROP -j DROP

	# SSH
	$ipt -A INPUT -s ${trusted} ${new_tcp_in} 22 -j ACCEPT # SSH
	$ipt -A INPUT ${new_tcp_in} 39018 -j ACCEPT # SSH-ALT

	# HTTP / HTTPS
	$ipt -A INPUT ${new_tcp_in} 80 -j ACCEPT # HTTP
	$ipt -A INPUT ${new_tcp_in} 443 -j ACCEPT # HTTPS

	# E-Mail related
	$ipt -A INPUT ${new_tcp_in} 25 -j ACCEPT # SMTP
	$ipt -A INPUT ${new_tcp_in} 110 -j ACCEPT # POP3
	$ipt -A INPUT ${new_tcp_in} 143 -j ACCEPT # IMAP
	$ipt -A INPUT ${new_tcp_in} 465 -j ACCEPT # SUBMISSION
	$ipt -A INPUT ${new_tcp_in} 587 -j ACCEPT # SMTPS
	$ipt -A INPUT ${new_tcp_in} 993 -j ACCEPT # IMAPS
	$ipt -A INPUT ${new_tcp_in} 993 -j ACCEPT # POP3S

	# MCS
	$ipt -A INPUT ${new_tcp_in} 25565:25575 -j ACCEPT # MCS


}

get_args() {
	
	while [[ "$1" ]] ; do

		case $1 in 

			-a|--accept)	default_policy="ACCEPT"		;;
			-d|--drop)	default_policy="DROP"		;;
			-r|--reject)	default_policy="REJECT"		;;
			-x|--debug)	set -o xtrace			;;
			-l|--lan)	if_lan="${2:-error}" ; shift	;;
			-w|--wan)	if_wan="${2:-error}" ; shift	;;
			-S|--ssh-only)  ssh_only="true"			;;
			*)		echo "$1: option not recognized";;
		esac
		shift
	done
}



start
