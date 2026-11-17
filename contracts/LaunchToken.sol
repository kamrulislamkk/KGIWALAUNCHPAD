// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title LaunchToken
/// @notice v2.1 fixed-allocation token with launchpad-only burns and ETH dividend accounting.
/// @dev ETH remains in the launchpad. Transfers preserve earned dividends, not future entitlement.
contract LaunchToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint256 public constant MAGNITUDE = 1 << 128;
    /// @dev Rewards are only distributed over at least this much circulating supply (1,000 tokens).
    /// A tiny denominator would blow up pointsPerShare and could overflow later transfers.
    uint256 public constant MIN_REWARD_SUPPLY = 1_000e18;
    address public immutable launchpad;
    uint256 public pointsPerShare;
    mapping(address => int256) public pointsCorrection;
    mapping(address => uint256) public withdrawn;

    error OnlyLaunchpad();
    error InvalidSupply();
    error InvalidAddress();
    error NoCirculatingSupply();
    error RewardOverflow();

    modifier onlyLaunchpad() {
        if (msg.sender != launchpad) revert OnlyLaunchpad();
        _;
    }

    /// @notice Mint exactly one billion tokens once to the deploying launchpad.
    /// @dev Constructor parameters are retained from v1; no subsequent mint path exists.
    constructor(string memory name, string memory symbol, uint256 supply, address mintTo)
        ERC20(name, symbol)
    {
        if (supply != TOTAL_SUPPLY) revert InvalidSupply();
        if (mintTo == address(0) || mintTo != msg.sender) revert InvalidAddress();
        launchpad = mintTo;
        _mint(mintTo, TOTAL_SUPPLY);
    }

    /// @notice Outstanding supply eligible for new rewards, excluding every launchpad-held token.
    function circulating() public view returns (uint256) {
        return totalSupply() - balanceOf(launchpad);
    }

    /// @notice Account for ETH already reserved by the launchpad, rounding down only.
    function addRewards(uint256 amount) external onlyLaunchpad {
        uint256 eligible = circulating();
        if (eligible < MIN_REWARD_SUPPLY) revert NoCirculatingSupply();
        pointsPerShare += Math.mulDiv(amount, MAGNITUDE, eligible);
    }

    /// @notice Unwithdrawn ETH entitlement; the excluded launchpad always has zero entitlement.
    function pendingRewards(address user) public view returns (uint256) {
        if (user == launchpad || user == address(0)) return 0;
        int256 corrected = _asInt(pointsPerShare * balanceOf(user)) + pointsCorrection[user];
        return uint256(corrected) / MAGNITUDE - withdrawn[user];
    }

    /// @notice Mark rewards consumed before returning their amount to the paying launchpad.
    function consumeRewards(address user) external onlyLaunchpad returns (uint256 owed) {
        owed = pendingRewards(user);
        withdrawn[user] += owed;
    }

    /// @notice Burn only from the launchpad's own inventory, never from a holder.
    function burn(uint256 amount) external onlyLaunchpad {
        _burn(launchpad, amount);
    }

    /// @dev Exclusion also covers unsold inventory and unclaimed fundraise allocations.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        int256 correction = _asInt(pointsPerShare * value);
        if (from != address(0) && from != launchpad) pointsCorrection[from] += correction;
        if (to != address(0) && to != launchpad) pointsCorrection[to] -= correction;
    }

    function _asInt(uint256 value) private pure returns (int256) {
        if (value > uint256(type(int256).max)) revert RewardOverflow();
        return int256(value);
    }
}
