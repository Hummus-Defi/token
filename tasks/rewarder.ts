import { ethers } from 'ethers'
import { task, types } from 'hardhat/config'

task('deploy-rewarder', 'Deploy a Rewarder')
  .addParam('lp', 'The address of the LP Token', ethers.constants.AddressZero, types.string)
  .addOptionalParam('rate', 'The amount of tokens to emit per second', '0', types.string)
  .addOptionalParam('reward', 'The address of the reward token, only if non-native', undefined, types.string)
  .setAction(async ({ lp, rate, reward }, { ethers, getNamedAccounts, run }) => {
    const { METIS, STAKING } = await getNamedAccounts()

    const factory = await ethers.getContractFactory('Rewarder')
    const rewarder = await factory.deploy(
      reward ?? METIS,
      lp,
      STAKING,
      ethers.utils.parseEther(rate),
      reward ? false : true
    )
    await rewarder.deployed()

    await run('verify:verify', {
      address: rewarder.address,
      constructorArguments: [reward ?? METIS, lp, STAKING, ethers.utils.parseEther(rate), reward ? false : true],
    })
  })

task('fund-rewarder', 'Fund a Rewarder')
  .addParam('rewarder', 'The address of the Rewarder to fund')
  .addParam('amount', 'The amount of tokens to send the Rewarder * 1e18')
  .setAction(async ({ rewarder, amount }, { ethers, getNamedAccounts }) => {
    const { deployer } = await getNamedAccounts()
    const signer = await ethers.getSigner(deployer)
    const tx = await signer.sendTransaction({
      to: rewarder,
      value: ethers.utils.parseEther(amount),
    })
    await tx.wait()
  })
