import { ethers, getNamedAccounts, upgrades } from "hardhat"

async function main() {
  const { ESCROW } = await getNamedAccounts()
  const oldEscrow = await ethers.getContractFactory('VeHumV2')
  const escrow = await ethers.getContractFactory('VeHumV3')

  const proxy = await upgrades.forceImport(ESCROW, oldEscrow)

  // initialize
  const upgrade = await upgrades.upgradeProxy(proxy, escrow, { unsafeAllow: ["delegatecall"]})
  await upgrade.deployed();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })