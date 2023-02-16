import { BigNumber, ethers } from 'ethers'
import { task, types } from 'hardhat/config'

task('deploy-bribe', 'Deploy a Rewarder')
  .addParam('lp', 'The address of the LP Token', ethers.constants.AddressZero, types.string)
  .addOptionalParam('rate', 'The amount of tokens to emit per second', '0', types.string)
  .addOptionalParam('reward', 'The address of the reward token, only if non-native', undefined, types.string)
  .setAction(async ({ lp, rate, reward }, { ethers, getNamedAccounts, run }) => {
    const { METIS, STAKING } = await getNamedAccounts()

    const factory = await ethers.getContractFactory('Rewarder')
    const rewarder = await factory.deploy(reward ?? METIS, lp, STAKING, rate, reward ? false : true)
    await rewarder.deployed()

    await run('verify:verify', {
      address: rewarder.address,
      constructorArguments: [reward ?? METIS, lp, STAKING, ethers.utils.parseEther(rate), reward ? false : true],
    })
  })