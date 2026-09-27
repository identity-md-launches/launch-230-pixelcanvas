// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PixelCanvas} from "../src/PixelCanvas.sol";
import {AdversarialToken} from "./helpers/AdversarialToken.sol";

contract ReentrantCollector {
    PixelCanvas public immutable wall;
    uint256 public creditDuringCallback;
    bool public reentered;
    bytes public reason;

    constructor(PixelCanvas wall_) {
        wall = wall_;
    }

    function paint(AdversarialToken token) external {
        token.approve(address(wall), type(uint256).max);
        wall.paint(0, 1);
    }

    function withdraw() external {
        wall.withdraw();
    }

    function onTokensReceived() external {
        creditDuringCallback = wall.withdrawable(address(this));
        (reentered, reason) = address(wall).call(abi.encodeCall(PixelCanvas.withdraw, ()));
    }
}

contract PixelCanvasAdversarialTest is Test {
    AdversarialToken private token;
    PixelCanvas private wall;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new AdversarialToken();
        wall = new PixelCanvas(address(token));
        token.transfer(ALICE, 1000 ether);
        token.transfer(BOB, 1000 ether);
        vm.prank(ALICE);
        token.approve(address(wall), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(wall), type(uint256).max);
    }

    function test_falseTransferFromRollsBackWholeBatch() public {
        token.setFailure(true, false, address(0));
        _failedBatch();
    }

    function test_failedBurnRollsBackCollectedTokensAndWholeBatch() public {
        token.setFailure(false, false, DEAD);
        _failedBatch();
    }

    function _failedBatch() private {
        uint256[] memory indices = new uint256[](2);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vm.prank(ALICE);
        wall.paintBatch(indices, new uint24[](2));
        assertEq(token.balanceOf(ALICE), 1000 ether);
        assertEq(token.balanceOf(address(wall)), 0);
        assertEq(token.balanceOf(DEAD), 0);
        assertEq(wall.withdrawable(ALICE), 0);
        assertEq(wall.painterOf(0), address(0));
        assertEq(wall.priceOf(0), 10 ether);
        assertEq(wall.canvas(), new bytes(3072));
        // The reverted nonReentrant call must not leave the guard locked.
        token.setFailure(false, false, address(0));
        vm.prank(ALICE);
        wall.paint(0, 1);
    }

    function test_failedWithdrawRestoresCreditAndDoesNotBlockOtherRecipients() public {
        vm.prank(ALICE);
        wall.paint(0, 1);
        vm.prank(BOB);
        wall.paint(0, 2);
        vm.prank(ALICE);
        wall.paint(0, 3);
        uint256 aliceBefore = token.balanceOf(ALICE);
        token.setFailure(false, false, ALICE);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vm.prank(ALICE);
        wall.withdraw();
        assertEq(wall.withdrawable(ALICE), 5.5 ether);
        assertEq(token.balanceOf(ALICE), aliceBefore);
        vm.prank(BOB);
        wall.withdraw();
        assertEq(wall.withdrawable(BOB), 0);
        assertEq(token.balanceOf(address(wall)), 5.5 ether);
        token.setFailure(false, false, address(0));
        vm.prank(ALICE);
        wall.withdraw();
        assertEq(token.balanceOf(address(wall)), 0);
    }

    function test_safeERC20AcceptsSuccessfulTransfersWithNoReturnData() public {
        token.setNoReturnData(true);
        vm.prank(ALICE);
        wall.paintBatch(new uint256[](2), new uint24[](2));
        assertEq(token.collectionCalls(), 1);
        assertEq(wall.withdrawable(ALICE), 5.5 ether);
        vm.prank(ALICE);
        wall.withdraw();
        assertEq(token.balanceOf(ALICE), 1000 ether - 15.5 ether);
        assertEq(token.balanceOf(DEAD), 15.5 ether);
        assertEq(token.balanceOf(address(wall)), 0);
    }

    function test_collectionAndBurnCallbacksCannotEnterAnyMutator() public {
        bytes[3] memory attacks = [
            abi.encodeCall(PixelCanvas.paint, (5, 1)),
            abi.encodeCall(PixelCanvas.paintBatch, (new uint256[](1), new uint24[](1))),
            abi.encodeCall(PixelCanvas.withdraw, ())
        ];
        for (uint256 i; i < attacks.length; ++i) {
            for (uint256 phase; phase < 2; ++phase) {
                token.setHook(address(wall), attacks[i], phase == 0, phase == 1);
                vm.prank(ALICE);
                wall.paint(0, 1);
                assertFalse(token.hookSucceeded());
                assertEq(
                    token.hookResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
                );
                assertEq(token.balanceOf(address(wall)), wall.withdrawable(ALICE));
            }
        }
    }

    function test_recipientReentrySeesZeroCreditAndCannotDoubleWithdraw() public {
        ReentrantCollector collector = new ReentrantCollector(wall);
        token.transfer(address(collector), 10 ether);
        collector.paint(token);
        vm.prank(BOB);
        wall.paint(0, 2);
        assertEq(wall.withdrawable(address(collector)), 5.5 ether);
        token.setHook(address(collector), abi.encodeCall(ReentrantCollector.onTokensReceived, ()), false, true);
        collector.withdraw();
        assertEq(collector.creditDuringCallback(), 0);
        assertFalse(collector.reentered());
        assertEq(collector.reason(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(token.balanceOf(address(collector)), 5.5 ether);
        assertEq(wall.withdrawable(address(collector)), 0);
        assertEq(token.balanceOf(address(wall)), 0);
    }
}
