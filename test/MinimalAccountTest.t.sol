// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "../src/MinimalAccount.sol";
import {DeployMinimal} from "../script/DeployAccount.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp} from "../script/SendPackedUserOp.s.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;

    address randomUser = makeAddr("randomUser");

    function setUp() external {
        DeployMinimal deployer = new DeployMinimal();
        (helperConfig, minimalAccount) = deployer.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    // Flow of test:
    // msg.sender -> MinimalAccount
    // approve some amount in the USDC contract and should come from the entry point

    function testOwnerCanExecuteCommands() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), 1e18);
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);
        assertEq(usdc.balanceOf(address(minimalAccount)), 1e18);
    }

    function testRecoverSignedOp() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), 1e18);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);

        PackedUserOperation memory userOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(userOp);

        (address signer,,) = ECDSA.tryRecover(userOpHash.toEthSignedMessageHash(), userOp.signature);

        assertEq(signer, minimalAccount.owner());
    }

    // 1. Sign user ops
    // 2. Call validate userOps
    // 3. Assert the return is correct
    function testValidateUserOps() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), 1e18);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);

        PackedUserOperation memory userOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(userOp);

        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(userOp, userOpHash, 1e18);
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommands() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), 1e18);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);

        PackedUserOperation memory userOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.deal(address(minimalAccount), 1e18);

        vm.prank(randomUser);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(randomUser));

        assertEq(usdc.balanceOf(address(minimalAccount)), 1e18);
    }
}
