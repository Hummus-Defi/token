import { ethers } from 'ethers'
import { task, types } from 'hardhat/config'

task('set-pool', 'Set the parameters of a pool')
  .addParam('pid', 'The pool id', undefined, types.int)
  .addParam('points', 'The base allocation points for the pool', undefined, types.int)
  .addOptionalParam('rewarder', 'The address of the Rewarder contract', ethers.constants.AddressZero, types.string)
  .addOptionalParam('overwrite', 'Whether to overwrite the Rewarder address', false, types.boolean)
  .setAction(async ({ pid, points, rewarder, overwrite }, { ethers, getNamedAccounts }) => {
    const { STAKING } = await getNamedAccounts()
    const farm = await ethers.getContractAt('MasterHummusV2', STAKING)
    const tx = await farm.set(pid, points, rewarder, overwrite)
    await tx.wait()
  })
