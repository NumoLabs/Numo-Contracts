#!/bin/bash

# Deploy VesuRebalance contract (V2) - Refactored for V2
# Class Hash: 0x07b23ad6a013abcf5858942b457fc51f99c15c14e6dd88fa86d8a3c9da45aedf
# Constructor params: name, symbol, asset, access_control, allowed_pools, settings, oracle
# In V2, constructor only needs oracle (not vesuStruct)

sncast --account aguilar1x deploy \
  --url https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_9/c0P2DVGVr0OOBtgc3tSqm \
  --class-hash 0x07b23ad6a013abcf5858942b457fc51f99c15c14e6dd88fa86d8a3c9da45aedf \
  --constructor-calldata \
  0 \
  0x4e756d6f205661756c74207742544300000000000000000000000000000000 \
  16 \
  0 \
  0x4e567742544300000000000000000000000000000000000000000000000000 \
  6 \
  0x03Fe2b97C1Fd336E750087D68B9b867997Fd64a2661fF3ca5A7C771641e8e7AC \
  0x038d9c69eed034ba4765920f7b3c9d57acf8ef447230c4529ddea660d42a6487 \
  1 \
  0x451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5 \
  10000 \
  0x4ecb0667140b9f45b067d026953ed79f22723f1cfac05a7b26c3ac06c88f56c \
  0 \
  100 \
  0x0466617918874f335728dbe0903376d1d9756137dd70e927164af4855e1ddae1 \
  0xfe4bfb1b353ba51eb34dff963017f94af5a5cf8bdf3dfc191c504657f3c05

