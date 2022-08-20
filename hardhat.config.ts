import 'dotenv/config'

import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-solhint'
// import '@nomiclabs/hardhat-etherscan'
import 'metis-sourcecode-verify'
import '@typechain/hardhat'
import '@openzeppelin/hardhat-upgrades'
import 'solidity-coverage'
import 'hardhat-abi-exporter'
import 'hardhat-deploy'
import 'hardhat-gas-reporter'
import 'hardhat-docgen'
import '@hardhat-docgen/core'
import '@hardhat-docgen/markdown'
import 'hardhat-contract-sizer'
import 'hardhat-spdx-license-identifier'

import { HardhatUserConfig } from 'hardhat/config'
import './tasks/rewarder'
import './tasks/staking'

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
  abiExporter: {
    flat: true,
    clear: true,
    runOnCompile: true,
    path: './build/abi',
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  mocha: {
    timeout: 200000,
  },
  namedAccounts: {
    deployer: 0,
    multisig: {
      1088: '0x08961b470a39bEE12435f3742aFaA70B64DCa893',
      default: 0,
    },

    // contracts
    STAKING: {
      // MasterHummusV2
      42: '0x765099591EA91DFAb032dD12cBFbe5976319FdF4',
      588: '0x248fD66e6ED1E0B325d7b80F5A7e7d8AA2b2528b',
      1088: '0x9cadd693cDb2B118F00252Bb3be4C6Df6A74d42C',
    },
    TOKEN: {
      // Hum
      42: '0xe8Eb8149ac20d75C5fAE054FE5C3A9688aCa8c67',
      588: '0x8b2AF921F3eaef0d9D6a47B65E1F7F83bEfB2f1f',
      1088: '0x4aAC94985cD83be30164DfE7e9AF7C054D7d2121',
    },
    ESCROW: {
      // veHum
      42: '0x955514d7e1DB34BB612c7a0Bbd63D25eA02dD29A',
      588: '0xd5A0760D55ad46B6A1C46D28725e4C117312a7aD',
      1088: '0x89351BEAA4AbbA563710864051a8C253E7b3E16d',
    },
    WHITELIST: {
      42: '0x927BADD28b3AF1156e9cCAb2F0FA3AFb13af8b65',
      588: '0x3878edF8E00fD8e29812A9379303F539ea012C5F',
      1088: '0xd5A67E95f21155f147be33562158a453Aa423840',
    },

    // lp assets

    HLPUSDC: {
      42: '0x0F6f2E19Bc2Ad2b847dd329A0D89DC0043003754',
      588: '0x8531939828265a346b4554b8e6478e6c12383952',
      1088: '0x9E3F3Be65fEc3731197AFF816489eB1Eb6E6b830',
    },
    HLPUSDT: {
      42: '0x44ba84500C5CeEB235653BA4952bc61F376847Ec',
      588: '0x9421c84388218e85f7274fe67ed316ffc524eb4b',
      1088: '0x9F51f0D7F500343E969D28010C7Eb0Db1bCaAEf9',
    },
    HLPDAI_OLD: {
      42: '0x53211440f038dBBe9DE1B9fa58757cb430ecb752',
      588: '0x1c03ec1cc105fb925fce78155dd81def896237f7',
      1088: '',
    },
    HLPDAI: {
      588: '0xad78bb846eaf59f3fab8088e905c9d525dd7b2f1',
      1088: '0xd5A0760D55ad46B6A1C46D28725e4C117312a7aD',
    },
    HLPUSDC_MAI: {
      588: '0xa179c9df25c4a80ecfa8ec3788d3c055b1b2bab2',
      1088: '',
    },
    HLPMAI: {
      588: '0x409862b7758577952971a0350935bca4a54c63c0',
      1088: '',
    },

    // tokens
    METIS: {
      588: '0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000',
      1088: '0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000',
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
    apiKey: {
      metisAndromeda: 'api-key',
      metisStardust: 'api-key',
    },
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
