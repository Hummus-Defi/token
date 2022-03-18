import { ethers, getNamedAccounts, upgrades } from 'hardhat'

async function main() {
  const { TOKEN, STAKING } = await getNamedAccounts()
  const VoteEscrowTokenFactory = await ethers.getContractFactory('VePtp')
  console.log('Deploying Vote Escrow Token...')
  const voteEscrowToken = await upgrades.deployProxy(
    VoteEscrowTokenFactory,
    [TOKEN, STAKING, ethers.constants.AddressZero],
    {
      unsafeAllow: ['delegatecall'],
    }
  )
  await voteEscrowToken.deployed()
  console.log('Deployed to:', voteEscrowToken.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
