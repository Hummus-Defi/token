import { ethers, upgrades } from 'hardhat'

async function main() {
  const StakingFactory = await ethers.getContractFactory('MasterPlatypus')
  console.log('Deploying Staking (No Initialization)')
  const staking = await upgrades.deployProxy(StakingFactory, [], {
    initializer: false,
    unsafeAllow: ['delegatecall'],
  })
  await staking.deployed()
  console.log('Deployed to:', staking.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
