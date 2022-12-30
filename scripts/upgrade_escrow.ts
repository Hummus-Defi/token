import { ethers, getNamedAccounts, upgrades } from "hardhat"

async function main() {
  const { ESCROW } = await getNamedAccounts()
  const escrow = await ethers.getContractFactory('VeHumV2')

  // initialize
  const upgrade = await upgrades.upgradeProxy(ESCROW, escrow, { unsafeAllow: ["delegatecall"]})
  await upgrade.deployed();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })