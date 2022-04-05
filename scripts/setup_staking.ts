import { parseEther } from 'ethers/lib/utils'
import { ethers, getNamedAccounts } from 'hardhat'

const HUM_PER_SEC = parseEther('1') //'913242009132420000'
const DIALUTION = 375
const START_TIMESTAMP = 0

async function main() {
  const { STAKING, TOKEN, ESCROW } = await getNamedAccounts()
  const staking = await ethers.getContractAt('MasterHummusV2', STAKING)

  // initialize
  const tx = await staking.initialize(TOKEN, ESCROW, HUM_PER_SEC, DIALUTION, START_TIMESTAMP)
  await tx.wait()
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
