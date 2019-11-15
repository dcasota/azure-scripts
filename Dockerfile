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
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip qemu azure-cli && \
	apt-get clean
	
# Set working directory so stuff doesn't end up in /
WORKDIR /root

# Install VMware modules from PSGallery
SHELL [ "pwsh", "-command" ]
RUN Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
RUN install-module Az

CMD ["/usr/bin/bash"]