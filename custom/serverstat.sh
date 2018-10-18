#!/usr/bin/env bash


# Text formatting

res=$(tput sgr0)
bold=$(tput bold)
underline=$(tput smul)
green=$(tput setaf 2) 
red=$(tput setaf 1)
yellow=$(tput setaf 3)
light_green=$(tput setaf 119)
light_blue=$(tput setaf 159)
orange=$(tput setaf 202)
cyan=$(tput setaf 6)

# General variables
day=$(date +%a, \ %d.%m.%y)
current_time=$(date +%H:%m:%S)

Services=( "mysql" "nginx" "iptables" "php7.2-fpm" "php7.3-fpm" )

hostname=$(uname -n)
kernel_version=$(uname -r | awk -F'-' '{print $1}')




