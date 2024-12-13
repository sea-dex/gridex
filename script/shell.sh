forge script --chain base-sepolia script/GridExTestnet.s.sol:GridExScript --rpc-url $BASE_TESTNET_RPC --broadcast  --etherscan-api-key $ETHERSCAN_API_KEY --verify
# usdc --verifier-url https://sepolia.basescan.org/
forge verify-contract -e $ETHERSCAN_API_KEY --chain-id 84532 0xdaa63945fae1d7f479248db5d4c7592e58ce41d5 test/utils/USDC.sol:USDC

forge verify-contract -e $ETHERSCAN_API_KEY --chain-id 84532 0xe08cd03b8873991320bb943ca43626ecedccffbe test/utils/WETH.sol:WETH

forge verify-contract -e $ETHERSCAN_API_KEY --chain-id 84532 0x2181c894e4c04d1eb0579570ea6e9030446ab086 src/GridEx.sol:GridEx --constructor-args $(cast abi-encode "constructor(address,address)" 0xe08cd03b8873991320bb943ca43626ecedccffbe 0xdaa63945fae1d7f479248db5d4c7592e58ce41d5)

forge verify-contract -e $ETHERSCAN_API_KEY --chain-id 84532 0xcd3f1944ebe850dda47b8b11d45368ba066b694a src/Router.sol:Router --constructor-args $(cast abi-encode "constructor(address)" 0x2181c894e4c04d1eb0579570ea6e9030446ab086)


# deploy Router
# 0x0F79d721eBB8A550dbD26FcaEb8119A04d68fe65
# 0xa4E6FcF1C6d0Cfd5e90382e55Ca61D0cfFECB9Da
forge create --chain-id 84532 --private-key $PRIVATE_KEY --rpc-url $BASE_TESTNET_RPC --verify -e $ETHERSCAN_API_KEY src/GridEx.sol:GridEx --constructor-args 0x2181c894e4c04d1eb0579570ea6e9030446ab086
