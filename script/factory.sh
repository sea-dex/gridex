forge create --rpc-url $ARB_TESTNET_RPC --private-key $PRIVATE_KEY src/Factory.sol:Factory

# test
forge create --rpc-url $ARB_TESTNET_RPC --verify -e $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY test/utils/WETH.sol:WETH

forge create --rpc-url $ARB_TESTNET_RPC --verify -e $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY test/utils/USDC.sol:USDC 
forge create --rpc-url $ARB_TESTNET_RPC --verify -e $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY test/utils/SEA.sol:SEA 

forge verify-contract -r $ARB_TESTNET_RPC -e $ETHERSCAN_API_KEY address contract-path

forge flatten  src/Factory.sol -o f.sol


/Users/guotie/.foundry/bin/cast call --rpc-url $ARB_TESTNET_RPC  --private-key $PRIVATE_KEY 0xc79B8Db74412f90FfbE22534792AED3A8d4a8dc8 "balanceOf(address)(uint256)" 0x49d531908840FDDaC744543d57CB21B91c3D9094

/Users/guotie/.foundry/bin/cast call --rpc-url $ARB_TESTNET_RPC --private-key $PRIVATE_KEY 0xC5d8D27Fb17680d403B237C51175b26c0E497577 "balanceOf(address,uint256)" 0x49d531908840FDDaC744543d57CB21B91c3D9094

/Users/guotie/.foundry/bin/cast call --rpc-url $ARB_TESTNET_RPC --private-key $PRIVATE_KEY 0xc79B8Db74412f90FfbE22534792AED3A8d4a8dc8 "mint(address,uint256)" 0x49d531908840FDDaC744543d57CB21B91c3D9094 10000000000000000000


/Users/guotie/.foundry/bin/cast call --rpc-url $ARB_TESTNET_RPC --private-key $PRIVATE_KEY 0xc79B8Db74412f90FfbE22534792AED3A8d4a8dc8 "transfer(address,uint256)" 0x49d531908840FDDaC744543d57CB21B91c3D9094 10000000000000000000

/Users/guotie/.foundry/bin/cast call --rpc-url $ARB_TESTNET_RPC --private-key $PRIVATE_KEY 0xc79B8Db74412f90FfbE22534792AED3A8d4a8dc8 "transfer(address,uint256)" 0x49d531908840FDDaC744543d57CB21B91c3D9094 10000000000000000000

