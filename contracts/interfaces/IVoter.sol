// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IVoter {
    function distribute(address _lpToken) external;

    function pendingHum(address _lpToken) external view returns (uint256);

    // lpToken => weight, equals to sum of votes for a LP token
    function weights(address _lpToken) external view returns (uint256);

    // user address => lpToken => votes
    function votes(address _user, address _lpToken) external view returns (uint256);
}