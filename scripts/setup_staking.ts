import { parseEther } from 'ethers/lib/utils'
import { ethers, getNamedAccounts } from 'hardhat'

const HUM_PER_SEC = '4629629629629629629' // parseEther('1')
const DIALUTION = 375
const START_TIMESTAMP = 1649890800 // 2022-04-13 11:00PM GMT (4:00PM PST)

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
