import { ethers, getNamedAccounts, upgrades } from 'hardhat'
import { deployRewarder } from './helpers/deploy'

async function main() {
  const { metis } = await getNamedAccounts()

  // await deployRewarder()
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
