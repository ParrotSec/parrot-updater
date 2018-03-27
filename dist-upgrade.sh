#!/bin/bash
set -e
DEBIAN_FRONTEND=noninteractive
apt update && apt -y --allow-downgrades --fix-broken --fix-missing dist-upgrade
