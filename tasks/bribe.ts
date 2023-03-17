import { BigNumber, ethers } from 'ethers'
import { task, types } from 'hardhat/config'

task('deploy-bribe', 'Deploy a Bribe')
  .addParam('lp', 'The address of the LP Token', ethers.constants.AddressZero, types.string)
  .addOptionalParam('reward', 'The address of the reward token, only if non-native', undefined, types.string)
  .addOptionalParam('tokenPerSec', 'The amount of tokens to emit per second', '0', types.string)
  .setAction(async ({ lp, reward, tokenPerSec }, { ethers, getNamedAccounts, run }) => {
    const { METIS, VOTER } = await getNamedAccounts()

    const factory = await ethers.getContractFactory('Bribe')
    const bribe = await factory.deploy(VOTER, lp, reward ?? METIS, tokenPerSec, reward ? false : true)
    await bribe.deployed()


    await run('verify:verify', {
      address: bribe.address,
      constructorArguments: [VOTER, lp, reward ?? METIS, tokenPerSec, reward ? false : true],
    })
  })