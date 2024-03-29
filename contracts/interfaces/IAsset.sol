// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @dev Interface of Asset
 */
interface IAsset is IERC20 {
    function cash() external view returns (uint256);

    function liability() external view returns (uint256);
}
