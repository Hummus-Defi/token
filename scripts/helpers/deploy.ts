import { BigNumberish } from 'ethers'
import { ethers } from 'hardhat'

export const deployRewarder = async (
  rewardToken: string,
  lpToken: string,
  tokenPerSec: BigNumberish,
  farm: string,
  isNative: boolean
) => {
  const RewarderFactory = await ethers.getContractFactory('Rewarder')
  console.log(`Deploying Rewarder for ${lpToken}...`)
  const rewarder = await RewarderFactory.deploy(rewardToken, lpToken, tokenPerSec, farm, isNative)
  await rewarder.deployed()
  console.log('Deployed to:', rewarder.address)
}
