#!/usr/bin/env bash

# Run Plenary tests for syringe.nvim
nvim --headless \
  -c "set rtp+=$HOME/.local/share/nvim/lazy/plenary.nvim" \
  -c "set rtp+=." \
  -c "runtime! plugin/plenary.vim" \
  -c "PlenaryBustedDirectory tests {keep_going = false}"
