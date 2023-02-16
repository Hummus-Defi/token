import { ethers, getNamedAccounts, upgrades } from 'hardhat'

const DILUTION = 375

async function main() {
  const { TOKEN, ESCROW, VOTER } = await getNamedAccounts()
  const StakingFactory = await ethers.getContractFactory('MasterHummusV3')
  console.log('Deploying MasterHummusV3...')
  const staking = await upgrades.deployProxy(StakingFactory,
    [TOKEN, ESCROW, VOTER, DILUTION], 
    {
      unsafeAllow: ['delegatecall'],
    }
  )
  await staking.deployed()
  console.log('Deployed to:', staking.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
