import { ethers, getNamedAccounts } from 'hardhat'

const MINTING_TIMESTAMP = 1681948800 // 2023/04/20 12:00 AM GMT
// const MINTING_TIMESTAMP = 1705270000 // Metis Sepolia

async function main() {
  const { deployer, multisig } = await getNamedAccounts()
  const TokenFactory = await ethers.getContractFactory('Hum')
  console.log('Deploying Token...')
  const token = await TokenFactory.deploy(deployer, multisig, MINTING_TIMESTAMP)
  await token.deployed()
  console.log('Deployed to:', token.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
