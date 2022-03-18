import { ethers } from 'hardhat'

async function main() {
  const WhitelistFactory = await ethers.getContractFactory('Whitelist')
  console.log('Deploying Whitelist...')
  const whitelist = await WhitelistFactory.deploy()
  await whitelist.deployed()
  console.log('Deployed to:', whitelist.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
