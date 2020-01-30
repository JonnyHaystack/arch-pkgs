#!/bin/bash

# Get card number from aplay -l
CARD=$(aplay -l | grep "Logitech G430" | awk '{print $2}' | sed 's/[^0-9]*//g')

# Set sidetone using amixer
if [ -n $CARD ]; then
  amixer -c $CARD cset name='Mic Playback Volume' 27
fi
