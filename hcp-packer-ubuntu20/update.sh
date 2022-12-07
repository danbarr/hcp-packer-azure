#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
echo "Updating packages..."
apt-get -qq -y update >/dev/null && 
    apt-get -qq -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" dist-upgrade >/dev/null &&
    apt-get -qq -y clean >/dev/null 
