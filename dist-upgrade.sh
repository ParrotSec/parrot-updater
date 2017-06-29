#!/bin/bash
set -e
DEBIAN_FRONTEND=noninteractive
apt update && apt -y dist-upgrade
