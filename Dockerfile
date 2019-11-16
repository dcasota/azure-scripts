# Dockerfile for XY
#
# This Dockerfile provisions XY
#
#
# History
# 0.1  15.11.2019   dcasota  UNFINISHED! WORK IN PROGRESS!
#
#
# ---------------------------------------------------------------
FROM microsoft/powershell:ubuntu16.04

ENV TERM linux

WORKDIR /root

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip qemu azure-cli wget && \
	apt-get clean
	
# Set working directory so stuff doesn't end up in /
WORKDIR /root

# Install VMware modules from PSGallery
# SHELL [ "pwsh", "-command" ]
# RUN Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
# RUN install-module Az

RUN apt-get install build-essential libssl-dev -y && \
	apt-get install -y libssl-dev && \
	apt-get install -y zfsutils-linux  && \
	arch="$(uname -m)"  && \
	release="$(uname -r)"  && \
	upstream="${release%%-*}"   && \
	local="${release#*-}"  && \
	mkdir -p /usr/src && \
	wget -O "/usr/src/linux-${upstream}.tar.xz" "https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${upstream}.tar.xz" && \
	tar xf "/usr/src/linux-${upstream}.tar.xz" -C /usr/src/ && \

CMD ["/bin/bash"]