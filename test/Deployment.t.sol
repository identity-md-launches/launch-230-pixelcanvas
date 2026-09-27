// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {PixelCanvas} from "../src/PixelCanvas.sol";

/// @dev Reproduces factory constructor semantics without environment variables or broadcasting.
contract DeploymentFactoryProbe {
    function deploy() external returns (LaunchToken token, PixelCanvas wall) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        wall = new PixelCanvas{salt: bytes32(uint256(2))}(address(token));
    }
}

contract DeploymentTest is Test {
    function test_factoryConstructionKeepsSupplyAndNeedsNoFundingOrInitialization() public {
        vm.chainId(11155111);
        DeploymentFactoryProbe factory = new DeploymentFactoryProbe();
        (LaunchToken token, PixelCanvas wall) = factory.deploy();
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(wall)), 0);
        assertEq(address(wall.token()), address(token));
        assertEq(wall.priceOf(0), 10 ether);
        assertEq(wall.painterOf(0), address(0));
        _checkRuntime(address(token));
        _checkRuntime(address(wall));
    }

    function _checkRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }
}
