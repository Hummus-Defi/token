import { ethers } from 'hardhat'

export const add = async (poolAddress: string, allocPoint: number, lpToken: string, rewarder: string) => {
  const pool = await ethers.getContractAt('MasterHummus', poolAddress)
  const tx = await pool.add(allocPoint, lpToken, rewarder)
  await tx.wait()
}
