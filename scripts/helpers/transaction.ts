import { ethers } from 'hardhat'

export const add = async (poolAddress: string, allocPoint: number, lpToken: string, rewarder: string) => {
  const pool = await ethers.getContractAt('MasterHummus', poolAddress)
  const tx = await pool.add(allocPoint, lpToken, rewarder)
  await tx.wait()
}

export const addV3 = async (poolAddress: string, lpToken: string, rewarder: string) => {
  const pool = await ethers.getContractAt('MasterHummusV3', poolAddress)
  const tx = await pool.add(lpToken, rewarder)
  await tx.wait()
}

export const addVoter = async (voterAddress: string, gaugeAddress: string, lpToken: string, bribe: string) => {
  const voter = await ethers.getContractAt('Voter', voterAddress)
  const tx = await voter.add(gaugeAddress, lpToken, bribe)
  await tx.wait()
}
