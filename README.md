# ApeBlendr Contracts

This repository contains the smart contracts for the ApeBlendr protocol. ApeBlendr is a no-loss savings game inspired by PoolTogether and built on top of the ApeCoin protocol.

## ApeBlendr address on Ethereum Goerli

https://goerli.etherscan.io/address/0xEc3A10A645a30BE7de559E365131FBbC94edCcc6

## ApeCoin address on Ethereum Goerli

https://goerli.etherscan.io/address/0x328507DC29C95c170B56a1b3A758eB7a9E73455c

## ApeCoinStaking address on Ethereum Goerli

https://goerli.etherscan.io/address/0x146FD8C08baf234e3566C0c694eDad4833403C6b

### Installation

```console
$ yarn
```

### Compile

```console
$ yarn compile
```

This task will compile all smart contracts in the `contracts` directory.
ABI files will be automatically exported in `artifacts` directory.

### Testing

```console
$ yarn test
```

### Code coverage

```console
$ yarn coverage
```

The report will be printed in the console and a static website containing full report will be generated in `coverage` directory.

### Code style

```console
$ yarn prettier
```

### Verify & Publish contract source code

```console
$ npx hardhat  verify --network mainnet $CONTRACT_ADDRESS $CONSTRUCTOR_ARGUMENTS
```
