# WIP
This is a WIP project of a Token-based Plasma Cash Implementations. This implementations only support ERC712 tokens. This repo corresponds to the contracts
and Ethereum-related file, in the 3-repo project.

API Side Chain     - https://github.com/epord/Plasma-Cash-SideChain

Front End Client   - https://github.com/epord/CryptoMons-client

Ethereum Contracts - https://github.com/epord/Plasma-Cash-RootChain

The main Contract is located at contracts/Core/RootChain.sol.

# How to deploy

## Requirements
You must have downloaded [Truffle](https://truffleframework.com/) and [Ganache-cli](https://truffleframework.com/ganache).
 
## Steps
1. `ganache-cli -p 7545 -i 5777 --gasLimit=0x1fffffffffffff --allowUnlimitedContractSize -e 1000000000`. Runs Ganache on port `7545`, `localhost` and network ID `5777`. Add the gasLimit, allowUnlimitedContractSize to be able to deploy big contracts. If you dont want to change 
2. `npm i`
3. `truffle migrate`

# Test

You can use [Remix](https://remix.ethereum.org/) and [Metamask](https://metamask.io/). 
You can also test it using our WIP client and API.

## Using the client

### Setup
1. Clone the [Front-End Client](https://github.com/epord/CryptoMons-client)
2. Clone the [API Side Chain](https://github.com/epord/Plasma-Cash-SideChain)
3. After truffle migrate, copy json the files in build/contracts of `CrytoMons`, `ValidatorManagerContract` and `RootChain` into the Api's src/json folder (override)
4. Setup Metamask network (Add a custom RPC -> http://localhost:7545 network 5777)
5. Import an account to Metamask using ganache's provided privateKey

### Run transactions
1. Follow the Readme in each project.
2. Open `localhost:8080` to use the client, make sure the API is running

## Using Remix

### Setup
1. After truffle migrate, save the contract address of CryptoMon, RootChain and ValidatorManagerContract
1. Setup Metamask network (Add a custom RPC -> http://localhost:7545 network 5777) with one of the chain's private keys
2. Import an account to Metamask using ganache's provided privateKey

### Run Transactions
1. Install [truffle-flattener](https://www.npmjs.com/package/truffle-flattener)
2. run `truffle-flattener contracts/Core/Rootchain.sol >> RootChainOut.sol`
2. run `truffle-flattener contracts/Core/CryptoMons.sol >> CryptoMonsOut.sol`
4. Copy RootChainOut and CryptoMonsOut into Remix
5. Compile the contracts (use 0.5.2 compiler if you want to debug)
7. On the `Deploy and Run Transactions` tab, make sure to use Injected Web3 and select the network in Metamask
8. Select `CryptoMons` and Add `At Address` copying the contract's address
9. Select `ValidatorManagerContract` and Add `At Address` copying the contract's address
10. Select `RootChain` and Add `At Address` copying the contract's address
11. In the `ValidatorManagerContract` make sure to setToken of `CryptMons` contract to `true`
12. Buy a `CryptMon` paying 0.01 eth, and safeTransfer it to `RootChain` address
13. Your token is now deposited



# Useful Commands
Run another terminal for using the following commands

- Fast-forward time (30 days):
```curl -H "Content-Type: application/json" -X POST --data         '{"id":1337,"jsonrpc":"2.0","method":"evm_increaseTime","params":[2592000]}' http://localhost:7545```
- Mine block in ganache
```curl -H "Content-Type: application/json" -X POST --data         '{"id":1337,"jsonrpc":"2.0","method":"evm_mine","params":[]}'         http://localhost:7545```
- Useful ganache commands:
```https://github.com/trufflesuite/ganache-cli#implemented-methods```