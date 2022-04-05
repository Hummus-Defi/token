# Core Deployment

Add the `.openzeppelin` file for the network from `@hummus/stableswap` on the first run to re-use the proxy admin.

Deploy Token. Set `TOKEN` variable address in `hardhat.config.ts`.

```
npx hardhat run scripts/deploy_token.ts
```

Deploy Whitelist. Set `WHITELIST` variable address in `hardhat.config.ts`.

```
npx hardhat run scripts/deploy_whitelist.ts
```

Deploy Staking w/o initialization. Set `STAKING` variable address in `hardhat.config.ts`.

```
npx hardhat run scripts/deploy_staking.ts
```

Deploy and initialize Vote Escrow Token. Set `ESCROW` variable address in `hardhat.config.ts`.

```
npx hardhat run scripts/deploy_escrow.ts
```

## Staking Setup

Initialize Staking

```
npx hardhat run scripts/setup_staking.ts
```

Add USD Assets to Staking

```
npx hardhat run scripts/add_staking_usd.ts
```
