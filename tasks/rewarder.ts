import { BigNumber, ethers } from 'ethers'
import { task, types } from 'hardhat/config'

task('deploy-rewarder', 'Deploy a Rewarder')
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

task('deploy-verewarder', 'Deploy a VeRewarder')
  .addParam('lp', 'The address of the LP Token', ethers.constants.AddressZero, types.string)
  .addOptionalParam('rate', 'The amount of tokens to emit per second', '0', types.string)
  .addOptionalParam('dialutingRepartition', 'The dialuting reward portion', 375, types.int)
  .addOptionalParam('reward', 'The address of the reward token, only if non-native', undefined, types.string)
  .setAction(async ({ lp, rate, dialutingRepartition, reward }, { ethers, getNamedAccounts, run }) => {
    const { METIS, STAKING, ESCROW } = await getNamedAccounts()

    const args = [reward ?? METIS, lp, STAKING, ESCROW, rate, dialutingRepartition, reward ? false : true]

    console.log('Deploying VeRewarder...')
    const factory = await ethers.getContractFactory('VeRewarder')
    const rewarder = await factory.deploy(...args)
    await rewarder.deployed()
    console.log('Deployed to:', rewarder.address)

    await run('verify:verify', {
      address: rewarder.address,
      constructorArguments: args,
    })
  })

  task('deploy-vehumrewarder', 'Deploy a VeHumRewarder')
  .addOptionalParam('rate', 'The amount of tokens to emit per second', '0', types.string)
  .addOptionalParam('reward', 'The address of the reward token, only if non-native', undefined, types.string)
  .setAction(async ({ rate, reward }, { ethers, getNamedAccounts, run }) => {
    const { METIS, ESCROW } = await getNamedAccounts()

    const args = [reward ?? METIS, ESCROW, rate, reward ? false : true]

    console.log('Deploying VeHumRewarder...')
    const factory = await ethers.getContractFactory('VeHumRewarder')
    const rewarder = await factory.deploy(...args)
    await rewarder.deployed()
    console.log('Deployed to:', rewarder.address)

    await run('verify:verify', {
      address: rewarder.address,
      constructorArguments: args,
    })
  })

task('fund-rewarder', 'Fund a Rewarder')
  .addParam('rewarder', 'The address of the Rewarder to fund', undefined, types.string)
  .addParam('amount', 'The amount of tokens to send the Rewarder', '0', types.string)
  .setAction(async ({ rewarder, amount }, { ethers, getNamedAccounts }) => {
    const { deployer } = await getNamedAccounts()
    const signer = await ethers.getSigner(deployer)
    const tx = await signer.sendTransaction({
      to: rewarder,
      value: BigNumber.from(amount),
    })
    await tx.wait()
  })
