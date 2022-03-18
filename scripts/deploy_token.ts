import { ethers, getNamedAccounts } from 'hardhat'

const MINTING_TIMESTAMP = 1681948800 // 2022/04/20 12:00 AM GMT

async function main() {
  const { deployer } = await getNamedAccounts()
  const TokenFactory = await ethers.getContractFactory('Ptp')
  console.log('Deploying Token...')
  const token = await TokenFactory.deploy(deployer, deployer, MINTING_TIMESTAMP)
  await token.deployed()
  console.log('Deployed to:', token.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
