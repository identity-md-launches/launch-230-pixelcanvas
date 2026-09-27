// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../../src/LaunchToken.sol";
import {PixelCanvas} from "../../src/PixelCanvas.sol";

abstract contract CanvasFixture is Test {
    LaunchToken internal token;
    PixelCanvas internal wall;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    event Painted(uint256 indexed index, uint24 colour, address indexed painter, uint256 price);
    event Withdrawn(address indexed account, uint256 amount);

    function setUp() public virtual {
        token = new LaunchToken();
        wall = new PixelCanvas(address(token));
        _fund(ALICE);
        _fund(BOB);
        _fund(CAROL);
    }

    function _fund(address account) internal {
        token.transfer(account, 250_000_000 ether);
        vm.prank(account);
        token.approve(address(wall), type(uint256).max);
    }

    function _paint(address account, uint256 index, uint24 colour) internal {
        vm.prank(account);
        wall.paint(index, colour);
    }

    function _assertAccounting() internal view {
        uint256 credits = wall.withdrawable(ALICE) + wall.withdrawable(BOB) + wall.withdrawable(CAROL);
        assertEq(token.balanceOf(address(wall)), credits);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CAROL)
                + token.balanceOf(DEAD) + token.balanceOf(address(wall)),
            token.totalSupply()
        );
    }
}
