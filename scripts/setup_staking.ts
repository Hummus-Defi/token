import { ethers, getNamedAccounts } from 'hardhat'

const HUM_PER_SEC = '913242009132420000'
const DIALUTION = 375
const START_TIMESTAMP = 0

async function main() {
  const { STAKING, TOKEN, VE_TOKEN } = await getNamedAccounts()
  const staking = await ethers.getContractAt('MasterHummus', STAKING)

  // initialize
  const tx = await staking.initialize(TOKEN, VE_TOKEN, HUM_PER_SEC, DIALUTION, START_TIMESTAMP)
  await tx.wait()
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
