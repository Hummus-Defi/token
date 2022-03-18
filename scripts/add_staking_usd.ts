import { ethers, getNamedAccounts } from 'hardhat'
import { add } from './helpers/transaction'

async function main() {
  const { STAKING, HLPDAI, HLPUSDC, HLPUSDT } = await getNamedAccounts()

  await add(STAKING, 100, HLPDAI, ethers.constants.AddressZero)
  await add(STAKING, 100, HLPUSDC, ethers.constants.AddressZero)
  await add(STAKING, 100, HLPUSDT, ethers.constants.AddressZero)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
