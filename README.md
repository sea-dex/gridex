
## Documentation

A decentralized exchange (DEX) based on grid order is an innovative platform for trading digital assets that leverages the principles of grid order trading within a decentralized framework. Unlike traditional centralized exchanges, which rely on a central authority to facilitate transactions, DEXs operate on blockchain technology, allowing users to trade directly with each other without the need for intermediaries.

In a DEX utilizing grid order, the trading system is structured around a grid-like pattern of buy and sell orders, much like in traditional grid order trading strategies. However, in this decentralized context, the execution of trades occurs directly on the blockchain through smart contracts, ensuring transparency, security, and autonomy.

Key features of a DEX based on grid order include:

* **Grid Order Trading**
The DEX employs a grid order trading system, where users can place buy and sell orders at predefined price intervals. These orders are executed autonomously by smart contracts when the market price reaches specified levels, enabling users to profit from price fluctuations.

* **Decentralization**
Being decentralized, the exchange operates without a central authority or intermediary. Trades are executed peer-to-peer, eliminating the need for trust in a third party and reducing the risk of censorship or manipulation.

* **Transparency and Security**
All transactions on the DEX are recorded on the blockchain, providing a transparent and immutable ledger of trading activity. This enhances security and ensures the integrity of the trading process.

* **User Control**
Users maintain full control of their funds throughout the trading process. Since trades are executed directly from users' wallets through smart contracts, there is no need to deposit funds into a centralized exchange, reducing the risk of loss due to hacks or security breaches.

* **Customizable Strategies**
Traders can customize their grid order trading strategies based on their preferences and market conditions. They can adjust parameters such as grid spacing, order size, and risk management settings to optimize their trading approach.

Overall, a decentralized exchange based on grid order combines the benefits of grid trading strategies with the advantages of decentralization, providing users with a secure, transparent, and efficient platform for trading digital assets.

## Usage

see https://docs.seadex.org

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

create mock tokens: WETH USDC
```
forge create --broadcast test/utils/USDC.sol:USDC --rpc-url https://sepolia.base.org --private-key
forge create --broadcast test/utils/WETH.sol:WETH --rpc-url https://sepolia.base.org --private-key
```

```shell
$ forge create --broadcast src/GridEx.sol:GridEx --rpc-url https://sepolia.base.org --private-key <your_private_key> --constructor-args 
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
