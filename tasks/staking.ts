import { task } from 'hardhat/config'

task('set-pool', 'Set the parameters of a pool')
  .addParam('pid', 'The pool id')
  .addParam('baseAllocPoint', 'The base allocation points for the pool')
  .addOptionalParam('rewarder', 'The address of the Rewarder contract')
  .setAction(async ({ pid, baseAllocPoint, rewarder }, { ethers, getNamedAccounts }) => {
    const { STAKING } = await getNamedAccounts()
    const farm = await ethers.getContractAt('MasterHummusV2', STAKING)

    const tx = await farm.set(pid, baseAllocPoint, rewarder ?? ethers.constants.AddressZero, rewarder ? true : false)
    await tx.wait()
  })
