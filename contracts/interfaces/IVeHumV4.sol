// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import './IVeERC20.sol';

/**
 * @dev Interface of the VeHum
 */
interface IVeHumV4 is IVeERC20 {
    function isUser(address _addr) external view returns (bool);

    function deposit(uint256 _amount) external;

    function claim() external;

    function withdraw(uint256 _amount) external;

    function stakeNft(uint256 _tokenId) external;

    function unstakeNft() external;

    function vote(address _user, int256 _voteDelta) external;

    function getStakedNft(address _addr) external view returns (uint256);

    function getStakedHum(address _addr) external view returns (uint256);

    function getVotes(address _account) external view returns (uint256);
}