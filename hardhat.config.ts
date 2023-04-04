import 'dotenv/config'

import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-solhint'
import '@nomiclabs/hardhat-etherscan'
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
import './tasks/bribe'

const config: HardhatUserConfig = {
  networks: {
    goerli: {
      url: 'https://goerli.gateway.metisdevops.link',
      chainId: 599,
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
    outDir: './build/typechain',
    target: 'ethers-v5',
  },
  abiExporter: {
    flat: false,
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
      // 599: '0x838b73a945cF42e07f316a9d0a5715e8B5B973c9',
      599: '0x871BD2Ad5D27568D09BEd1Baa31cCa20F4f73BCe',
      1088: '0x9cadd693cDb2B118F00252Bb3be4C6Df6A74d42C',
    },
    TOKEN: {
      // Hum
      599: '0x9cadd693cDb2B118F00252Bb3be4C6Df6A74d42C',
      1088: '0x4aAC94985cD83be30164DfE7e9AF7C054D7d2121',
    },
    ESCROW: {
      // VeHumV2
      599: '0x5FfdD3A5DF7fdB5f3206E25B09681B4b11de4180',
      1088: '0x89351BEAA4AbbA563710864051a8C253E7b3E16d',
    },
    WHITELIST: {
      599: '0xb999a120CBB6a6e01Ae8e5fAdBebD2014731F8D8',
      1088: '0xd5A67E95f21155f147be33562158a453Aa423840',
    },
    VOTER: {
      599: '0x5ec678ff6B18D25942735cba117640898aF195A3',
      1088: '0xCfe81Cc985a7Bc7715CcA856EDc2517059ec7b37',
    },
    STAKING_V3: {
      599: '0x0776Ce3aD98Eb160fc75b67A4CD55C0976B0A597',
      1088: '0x9c3cdE31f153FBCE9Bbee1fa9a6596AbE9BA40fC',
    },

    // lp assets - listed in PID order

    HLPUSDC: {
      599: '0x25748645193FD23102CEFE2f62Ea688E17afFBC5',
      1088: '0x9E3F3Be65fEc3731197AFF816489eB1Eb6E6b830',
    },
    HLPUSDT: {
      599: '0x26083dD68999f46B79783DD25Fd2ed094ef7EAe8',
      1088: '0x9F51f0D7F500343E969D28010C7Eb0Db1bCaAEf9',
    },
    HLPDAI: {
      599: '0x2e08D7A362a4d45Da76429a04E3DC6019E145794',
      1088: '0xd5A0760D55ad46B6A1C46D28725e4C117312a7aD',
    },
    HLPDAI_V2: {
      599: '0x1BF3c7B140867293F131548222DC1B5dD0baEd2B',
      1088: '0x0CAd02c4c6fB7c0d403aF74Ba9adA3bf40df6478',
    },
    HLPUSDC_MAI: {
      599: '0x56990c5c86fe2afFdd9c7d28b9f85ef1C7a691Fe',
      1088: '0x8a19e755610aECB3c55BdE4eCfb9185ef0267400',
    },
    HLPMAI: {
      599: '0x2545b20912DeECa12a29BE7F6DCD9A5a56630eBf',
      1088: '0x3Eaa426861a283F0E46b6411aeB3C3608B090E0e',
    },
    HLPBUSD: {
      599: '0x3bfAAD9C299Af01AF1eB1c51cd934753dA000531',
      1088: '0x919395161Dd538aa0fB065A8EaC878B18D07FbCd',
    },

    // tokens
    METIS: {
      599: '0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000',
      1088: '0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000',
    },
    QI: {
      599: '0x5d7FB1329d87467752a6Eb82Bca2530152992020',
      1088: '0x3F56e0c36d275367b8C502090EDF38289b3dEa0d',
    },
  },
  // docgen: {
  //   path: './docs',
  //   clear: true,
  //   runOnCompile: false,
  //   except: ['/test/*', '/mock/*', '/hardhat-proxy/*'],
  // },
  etherscan: {
    apiKey: 'api-key',
    customChains: [
      {
        network: "andromeda",
        chainId: 1088,
        urls: {
          apiURL: "https://andromeda-explorer.metis.io/api",
          browserURL: "https://andromeda-explorer.metis.io",
        },
      },
      {
        network: "goerli",
        chainId: 599,
        urls: {
          apiURL: "https://goerli.explorer.metisdevops.link/api",
          browserURL: "https://goerli.explorer.metisdevops.link",
        },
      },
    ],
  },
}

if (process.env.ACCOUNT_PRIVATE_KEYS) {
  config.networks = {
    ...config.networks,
    goerli: {
      ...config.networks?.goerli,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
    andromeda: {
      ...config.networks?.andromeda,
      accounts: JSON.parse(process.env.ACCOUNT_PRIVATE_KEYS),
    },
  }
}

config.gasReporter = {
  enabled: process.env.REPORT_GAS ? true : false,
}

export default config
