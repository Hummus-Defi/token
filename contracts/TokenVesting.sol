// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title TokenVesting
/// @notice Linear token vesting schedule with an optional cliff.
contract TokenVesting is Ownable {
    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);
    event TokenVestingRevoked(address token);

    address public immutable beneficiary;

    uint256 public immutable cliff;
    uint256 public immutable duration;
    uint256 public immutable start;
    uint256 public immutable end;

    mapping(address => uint256) public released;
    mapping(address => bool) public revoked;

    /// @param _beneficiary The address of the beneficiary
    /// @param _cliff The amount of seconds before unlocks start
    /// @param _vest The amount of seconds to linearly unlock tokens
    constructor(
        address _beneficiary,
        uint256 _cliff,
        uint256 _vest
    ) {
        require(_beneficiary != address(0), 'beneficiary is the zero address');

        beneficiary = _beneficiary;
        start = block.timestamp;
        cliff = start + _cliff;
        duration = _cliff + _vest;
        end = start + duration;
    }

    function release(IERC20 token) public {
        uint256 unreleased = releasable(token);
        require(unreleased > 0, 'no tokens are due');

        released[address(token)] = released[address(token)] + unreleased;
        token.safeTransfer(beneficiary, unreleased);
        emit TokensReleased(address(token), unreleased);
    }

    function revoke(IERC20 token) external onlyOwner {
        require(!revoked[address(token)], 'token already revoked');

        uint256 balance = token.balanceOf(address(this));

        uint256 unreleased = releasable(token);
        uint256 refund = balance - unreleased;

        revoked[address(token)] = true;

        token.safeTransfer(owner(), refund);

        emit TokenVestingRevoked(address(token));
    }

    function releasable(IERC20 token) public view returns (uint256) {
        return vested(token) - released[address(token)];
    }

    function vested(IERC20 token) public view returns (uint256) {
        uint256 currentBalance = IERC20(token).balanceOf(address(this));
        uint256 totalBalance = currentBalance + released[address(token)];

        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= end || revoked[address(token)]) {
            return totalBalance;
        } else {
            // note releasable amount starts vesting on the cliff and not on the start
            return ((totalBalance * (block.timestamp - cliff)) / (duration - (cliff - start)));
        }
    }
}
