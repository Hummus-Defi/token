import { ethers, getNamedAccounts } from 'hardhat'
import { add, addV3 } from './helpers/transaction'

async function main() {
  const { STAKING_V3, HLPDAI, HLPUSDC, HLPUSDT, HLPDAI_V2, HLPUSDC_MAI, HLPMAI, HLPBUSD, QUAD, HMSP, TRI } =
    await getNamedAccounts()

  await addV3(STAKING_V3, HLPUSDC, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HLPUSDT, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HLPDAI, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HLPDAI_V2, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HLPUSDC_MAI, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HLPMAI, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HLPBUSD, ethers.constants.AddressZero)
  await addV3(STAKING_V3, QUAD, ethers.constants.AddressZero)
  await addV3(STAKING_V3, HMSP, ethers.constants.AddressZero)
  await addV3(STAKING_V3, TRI, ethers.constants.AddressZero)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
