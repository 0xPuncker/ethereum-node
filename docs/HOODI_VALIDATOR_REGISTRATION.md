# Hoodi Validator Registration Guide

This guide distills the steps a staker needs to follow on the [Hoodi Launchpad](https://hoodi.launchpad.ethstaker.cc/en/overview) to register new validators on the Hoodi testnet. It combines the Launchpad walkthrough with the network-specific data published by the Hoodi team.

## Quick Links
- Launchpad: <https://hoodi.launchpad.ethstaker.cc>
- Network tutorial & docs: <https://hoodi.ethpandaops.io>
- Execution explorer: <https://hoodi.etherscan.io>
- Consensus explorer: <https://hoodi.beaconcha.in>
- JSON-RPC endpoint: `https://rpc.hoodi.ethpandaops.io`
- Faucet: <https://faucet.hoodi.ethpandaops.io>
- Deposit contract (Hoodi): `0x00000000219ab540356cBB839Cbe05303d7705Fa`

## Prerequisites
- **Testnet ETH**: 32 testnet ETH per validator. Use the faucet above and confirm balances on `hoodi.etherscan.io` before depositing.
- **Wallet on Hoodi**: Configure your wallet (e.g., MetaMask) with:
  - Network name: `Hoodi`
  - RPC URL: `https://rpc.hoodi.ethpandaops.io`
  - Chain ID: `560048` (`0x88bb0`)
  - Currency symbol: `ETH`
  - Block explorer: `https://hoodi.etherscan.io`
- **Execution & consensus clients**: Prepare one of each client with Hoodi support (`--hoodi` or equivalent flag) and make sure you can reach bootnodes in `hoodi.ethdisco.net`.
- **Validator client**: Choose a validator client compatible with your consensus client (Lighthouse, Lodestar, Nimbus, Prysm, Teku, etc.).
- **Key tooling**: Download the latest [ethstaker-deposit-cli release](https://github.com/ethstaker/ethstaker-deposit-cli/releases) for key generation. Verify checksums/signatures before executing.
- **Execution withdrawal address**: Decide which Hoodi execution-layer address will receive withdrawals and store it securely.

## Registration Workflow

### 1. Review Launchpad responsibilities
1. Open <https://hoodi.launchpad.ethstaker.cc/en/overview>.
2. Read every acknowledgement page. The Launchpad reiterates critical topics:
   - Your validator must stay online or risk missed rewards.
   - Double-signing or running duplicates can lead to slashing.
   - You control withdrawal credentials—keep mnemonics offline and never share them.
   - Deposits are irreversible; use testnet ETH only.
3. Confirm each checklist item before continuing. The Launchpad intentionally slows you down—do not skip it.

### 2. Generate validator keys & deposit data
1. Extract the Hoodi chain identifiers from the official metadata:
   - `genesis_fork_version`: `0x10000910`
   - `genesis_validator_root`: `0x212f13fc4df078b6cb7db228f1c8307566dcecf900867401a92023d7ba99cb5f`
2. Run `ethstaker-deposit-cli` from an air-gapped or otherwise secure host:

   ```bash
   ./deposit new-mnemonic \
     --num_validators 1 \
     --chain mainnet \
     --execution_address 0xYourHoodiWithdrawalAddress \
     --devnet_chain_setting '{"network_name":"hoodi","genesis_fork_version":"0x10000910","genesis_validator_root":"0x212f13fc4df078b6cb7db228f1c8307566dcecf900867401a92023d7ba99cb5f"}'
   ```

   - Adjust `--num_validators` for the number of validators you intend to run.
   - If re-using a mnemonic, add `--validator_start_index` with the next unused index.
   - The command produces keystore files (BLS keys) and a `deposit-data-*.json` file in `./validator_keys`.
3. Back up:
   - The mnemonic phrase (write-once, stored offline).
   - The `keystore-*.json` files (encrypted by the password you set).
   - The generated `deposit-data-*.json` file (used by the Launchpad).
4. Optional: generate BLS-to-execution change files now if you want execution withdrawals ready. Use the same `--devnet_chain_setting` values.

### 3. Prepare your clients
1. Sync an execution client (e.g., Geth, Nethermind, Besu, Erigon) with Hoodi network flags or config files from <https://github.com/eth-clients/hoodi>.
2. Sync a consensus client (e.g., Lighthouse, Nimbus, Prysm, Teku, Lodestar) using the matching Hoodi configuration:
   - Provide the `--network hoodi` flag or point to the published `config.yaml` and `genesis.ssz`.
   - Configure bootnodes via `hoodi.ethdisco.net` if the client does not ship them by default.
3. Keep both clients running and fully synced before you submit deposits—your validator must be ready when activated.

### 4. Submit deposits through the Launchpad
1. Return to <https://hoodi.launchpad.ethstaker.cc>, choose “Get started”, and select the number of validators you generated.
2. Upload the `deposit-data-*.json` file when prompted. The Launchpad validates signatures against the Hoodi fork parameters above.
3. Connect your wallet (MetaMask or equivalent) to the Hoodi network and confirm the deposit contract matches `0x00000000219ab540356cBB839Cbe05303d7705Fa`.
4. For each validator:
   - Review the summary (public key, withdrawal address, amount = 32 ETH).
   - Submit the transaction. Expect two confirmations: on the execution layer (visible on `hoodi.etherscan.io`) and on the consensus layer (visible on `hoodi.beaconcha.in`).
5. Wait for the Launchpad to display confirmation that all deposits have been broadcast and included.

### 5. Activate validators
1. Keep execution and consensus clients running; they will detect the deposit once processed by the beacon chain.
2. Import the keystore(s) into your validator client and start the validator service.
3. Monitor activation status on <https://hoodi.beaconcha.in/validators>; validators move from `pending` to `active` once the activation queue clears.
4. After activation:
   - Ensure attestations and block proposals succeed (check client logs and the beacon explorer).
   - Configure metrics, alerts, and backups.

## Ongoing Operations
- Apply client updates promptly—Hoodi tracks mainnet upgrades closely (Cancun/Deneb and future hard forks are already enabled).
- Consider running MEV-Boost with Hoodi relays if you want to experiment:
  - Flashbots: `https://boost-relay-hoodi.flashbots.net`
  - Aestus: `https://hoodi.aestus.live`
  - Titan: `https://hoodi.titanrelay.xyz`
  - Ultrasound: `https://relay-hoodi.ultrasound.money`
  - Bloxroute: `https://bloxroute.hoodi.blxrbdn.com`
- Use `hoodi.ethdisco.net` DNS discovery endpoints to diversify peers.
- Periodically export fresh backups of keystores and validator passwords.
- Track announcements in the [eth-clients/hoodi GitHub repository](https://github.com/eth-clients/hoodi) for scheduled upgrades and new tooling.

## Troubleshooting
- **Deposit not visible**: Verify the transaction on `hoodi.etherscan.io`. If confirmed, wait for the next beacon chain epoch and re-check `hoodi.beaconcha.in`.
- **Validator stuck pending**: Activation depends on the queue depth. The Launchpad’s final screen links to queue statistics; expect delays if many validators are joining.
- **Client fails to sync**: Re-download the Hoodi metadata (`config.yaml`, `genesis.ssz`, bootnodes) and confirm your client version includes Hoodi support.
- **Duplicate validator warning**: Never reuse the same keystore on multiple validator instances; stop the extra node immediately to avoid slashing.

Keeping these steps and references handy should make repeated validator registrations on Hoodi straightforward while mirroring what the Launchpad expects from participants.
