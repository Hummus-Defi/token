import { ethers, getNamedAccounts, upgrades } from "hardhat"

async function main() {
  const { STAKING } = await getNamedAccounts()
  const staking = await ethers.getContractFactory('MasterHummusV2')

  // initialize
  const upgrade = await upgrades.upgradeProxy(STAKING, staking, { unsafeAllow: ["delegatecall"]})
  await upgrade.deployed();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })