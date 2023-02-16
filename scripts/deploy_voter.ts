import { ethers, getNamedAccounts, upgrades } from 'hardhat'

const HUM_PER_SEC = 0
const START_TIMESTAMP = 0

async function main() {
  const { TOKEN, ESCROW } = await getNamedAccounts()
  const VoteEscrowTokenFactory = await ethers.getContractFactory('Voter')
  console.log('Deploying Voter...')
  const voteEscrowToken = await upgrades.deployProxy(
    VoteEscrowTokenFactory,
    [TOKEN, ESCROW, HUM_PER_SEC, START_TIMESTAMP],
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
