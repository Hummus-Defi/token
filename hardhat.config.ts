import 'dotenv/config'

import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-solhint'
import '@nomiclabs/hardhat-etherscan'
import '@typechain/hardhat'
import '@openzeppelin/hardhat-upgrades'
import 'solidity-coverage'
import 'hardhat-deploy'
import 'hardhat-gas-reporter'
import 'hardhat-docgen'
import '@hardhat-docgen/core'
import '@hardhat-docgen/markdown'
import 'hardhat-contract-sizer'

import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    mainnet: {
      url: process.env.ALCHEMY_API || '',
      gasPrice: 140 * 1000000000,
    },
    rinkeby: {
      url: process.env.RINKEBY_API || '',
      chainId: 4,
      gasPrice: 5 * 1000000000,
    },
    kovan: {
      url: process.env.KOVAN_API || '',
      chainId: 42,
      gasPrice: 2 * 1000000000,
    },
    stardust: {
      url: 'https://stardust.metis.io/?owner=588',
      chainId: 588,
    },
    andromeda: {
      url: 'https://andromeda.metis.io/?owner=1088',
      chainId: 1088,
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.9',
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000,
          },
        },
      },
    ],
  },
  typechain: {
    outDir: './build/typechain/',
    target: 'ethers-v5',
  },
  mocha: {
    timeout: 200000,
  },
  namedAccounts: {
    deployer: 0,

    // contracts

    STAKING: {
      42: '',
    },
    TOKEN: {
      42: '',
    },
    VE_TOKEN: {
      42: '',
    },

    // lp assets

    HLPDAI: {
      42: '0x53211440f038dBBe9DE1B9fa58757cb430ecb752',
    },
    HLPUSDC: {
      42: '0x0F6f2E19Bc2Ad2b847dd329A0D89DC0043003754',
    },
    HLPUSDT: {
      42: '0x44ba84500C5CeEB235653BA4952bc61F376847Ec',
    },
  },
  docgen: {
    path: './docs',
    clear: true,
    runOnCompile: false,
    except: ['/test/*', '/mock/*', '/hardhat-proxy/*'],
  },
  etherscan: {
    // API key for snowtrace.io
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
}

if (process.env.ACCOUNT_PRIVATE_KEYS) {
  config.networks = {
    ...config.networks,
    mainnet: {
      ...config.networks?.mainnet,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
    rinkeby: {
      ...config.networks?.rinkeby,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
    kovan: {
      ...config.networks?.kovan,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
    stardust: {
      ...config.networks?.stardust,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
    andromeda: {
      ...config.networks?.andromeda,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
  }
}

if (process.env.FORK_MAINNET && config.networks) {
  config.networks.hardhat = {
    forking: {
      url: process.env.ALCHEMY_API ? process.env.ALCHEMY_API : '',
    },
    chainId: 1,
  }
}

config.gasReporter = {
  enabled: process.env.REPORT_GAS ? true : false,
}

export default config
