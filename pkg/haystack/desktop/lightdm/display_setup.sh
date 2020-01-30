#!/bin/sh
xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --output eDP-1-1 --primary --auto --pos 0x312 --output HDMI-1-1 --auto --pos 1366x0
xrandr --dpi 96
