import { ethers, getNamedAccounts } from 'hardhat'
import { add } from './helpers/transaction'

async function main() {
  const { STAKING, HLPDAI, HLPUSDC, HLPUSDT, HLPDAI_V2, HLPUSDC_MAI, HLPMAI, HLPBUSD } = await getNamedAccounts()

  await add(STAKING, 100, HLPUSDC, ethers.constants.AddressZero)
  await add(STAKING, 100, HLPUSDT, ethers.constants.AddressZero)
  await add(STAKING, 0, HLPDAI, ethers.constants.AddressZero)
  await add(STAKING, 100, HLPDAI_V2, ethers.constants.AddressZero)
  await add(STAKING, 50, HLPUSDC_MAI, ethers.constants.AddressZero)
  await add(STAKING, 50, HLPMAI, ethers.constants.AddressZero)
  await add(STAKING, 100, HLPBUSD, ethers.constants.AddressZero)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
