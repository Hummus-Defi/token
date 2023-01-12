// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IVoter {
    function distribute(address _lpToken) external;

    function pendingHum(address _lpToken) external view returns (uint256);
}