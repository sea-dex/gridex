# base sepolia
# owner: 0xDCCE32a5913E4555b3C4Da3Bbb0F958555320C37
# weth: 0xb15BDeAAb6DA2717F183C4eC02779D394e998e91
# usdc: 0xe8D9fF1263C9d4457CA3489CB1D30040f00CA1b2
forge create --broadcast src/strategy/Linear.sol:Linear --rpc-url $RPC_URL --private-key $PRIVATE_KEY
forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY src/GridEx.sol:GridEx  --constructor-args \
    0xb15BDeAAb6DA2717F183C4eC02779D394e998e91 0xe8D9fF1263C9d4457CA3489CB1D30040f00CA1b2 0xDCCE32a5913E4555b3C4Da3Bbb0F958555320C37

# BASE

## RPC_URL=https://mainnet.base.org
## weth: 0x4200000000000000000000000000000000000006
## USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913

forge create --verify --broadcast src/strategy/Linear.sol:Linear --rpc-url $RPC_URL --private-key $PRIVATE_KEY
forge create --verify --broadcast src/libraries/Lens.sol:Lens --rpc-url $RPC_URL --private-key $PRIVATE_KEY
forge create --verify --broadcast src/GridEx.sol:GridEx --rpc-url $RPC_URL --private-key $PRIVATE_KEY --libraries \
    src/libraries/Lens.sol:Lens:0x2eFA10B869e41459c1B0eC7f31eb45768CF839D2   --constructor-args \
    0x4200000000000000000000000000000000000006 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 0xfEb3509b7099Db900995e964f4586043A3C4BBF1
