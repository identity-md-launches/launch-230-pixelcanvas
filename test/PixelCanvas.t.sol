// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PixelCanvas} from "../src/PixelCanvas.sol";
import {CanvasFixture} from "./helpers/CanvasFixture.sol";

contract PixelCanvasTest is CanvasFixture {
    function test_initialCanvasPricesAndPainters() public view {
        assertEq(address(wall.token()), address(token));
        assertEq(token.balanceOf(address(wall)), 0);
        assertEq(wall.canvas(), new bytes(3072));
        for (uint256 i; i < 1024; ++i) {
            assertEq(wall.priceOf(i), 10 ether);
            assertEq(wall.painterOf(i), address(0));
        }
    }

    function test_constructorRejectsZeroAndNonContractToken() public {
        vm.expectRevert(PixelCanvas.InvalidToken.selector);
        new PixelCanvas(address(0));
        vm.expectRevert(PixelCanvas.InvalidToken.selector);
        new PixelCanvas(ALICE);
    }

    function test_firstPaintBurnsEntirePriceAndEmitsEvent() public {
        uint256 beforeBalance = token.balanceOf(ALICE);
        vm.expectEmit(true, true, false, true, address(wall));
        emit Painted(32, 0xFF0000, ALICE, 10 ether);
        _paint(ALICE, 32, 0xFF0000);
        assertEq(token.balanceOf(ALICE), beforeBalance - 10 ether);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(wall.withdrawable(ALICE), 0);
        assertEq(wall.painterOf(32), ALICE);
        assertEq(wall.priceOf(32), 11 ether);
        assertEq(wall.priceOf(31), 10 ether);
        assertEq(token.totalSupply(), 1e27);
        _assertAccounting();
    }

    function test_packedColoursAreRGBAndDoNotCorruptNeighbours() public {
        uint256[7] memory indices = [uint256(0), 1, 9, 10, 31, 32, 1023];
        uint24[7] memory colours = [uint24(0x123456), 0xFFFFFF, 0x00FF00, 0xAB00EF, 0x000001, 0x010000, 0xFEDCBA];
        bytes memory expected = new bytes(3072);
        for (uint256 i; i < indices.length; ++i) {
            _paint(ALICE, indices[i], colours[i]);
            uint256 offset = indices[i] * 3;
            expected[offset] = bytes1(uint8(colours[i] >> 16));
            expected[offset + 1] = bytes1(uint8(colours[i] >> 8));
            expected[offset + 2] = bytes1(uint8(colours[i]));
        }
        assertEq(wall.canvas(), expected);
        _paint(BOB, 9, 0);
        expected[27] = 0;
        expected[28] = 0;
        expected[29] = 0;
        assertEq(wall.canvas(), expected);
        _assertAccounting();
    }

    function test_repaintCreditsPreviousPainterAndSelfRepaintIsAllowed() public {
        _paint(ALICE, 0, 1);
        _paint(BOB, 0, 2);
        assertEq(wall.withdrawable(ALICE), 5.5 ether);
        assertEq(token.balanceOf(DEAD), 15.5 ether);
        _paint(BOB, 0, 3);
        assertEq(wall.withdrawable(BOB), 6.05 ether);
        assertEq(token.balanceOf(DEAD), 21.55 ether);
        assertEq(wall.painterOf(0), BOB);
        _assertAccounting();
    }

    function test_oddRepaintPriceRoundsCreditDownAndBurnUp() public {
        for (uint256 i; i < 100 && wall.priceOf(4) % 2 == 0; ++i) {
            _paint(ALICE, 4, uint24(i));
        }
        uint256 price = wall.priceOf(4);
        assertEq(price % 2, 1, "must exercise an actual odd price");
        uint256 creditBefore = wall.withdrawable(ALICE);
        uint256 burnBefore = token.balanceOf(DEAD);
        _paint(BOB, 4, 0);
        assertEq(wall.withdrawable(ALICE) - creditBefore, price / 2);
        assertEq(token.balanceOf(DEAD) - burnBefore, price / 2 + 1);
        assertEq(wall.priceOf(4), price + price / 10);
        _assertAccounting();
    }

    function test_priceGrowthCrossesCapThenStaysCapped() public {
        uint256 expected = 10 ether;
        bool crossed;
        for (uint256 i; i < 150; ++i) {
            assertEq(wall.priceOf(3), expected);
            uint256 burnBefore = token.balanceOf(DEAD);
            uint256 creditBefore = wall.withdrawable(ALICE);
            _paint(ALICE, 3, uint24(i));
            uint256 credit = i == 0 ? 0 : expected / 2;
            assertEq(wall.withdrawable(ALICE) - creditBefore, credit);
            assertEq(token.balanceOf(DEAD) - burnBefore, expected - credit);
            uint256 next = expected + expected / 10;
            if (expected < 1_000_000 ether && next >= 1_000_000 ether) crossed = true;
            expected = next < 1_000_000 ether ? next : 1_000_000 ether;
            assertEq(wall.priceOf(3), expected);
            _assertAccounting();
        }
        assertTrue(crossed);
        assertEq(expected, 1_000_000 ether);
    }

    function test_batchRepeatedIndexUsesSequentialPricesAndOneCollection() public {
        _paint(ALICE, 7, 1);
        uint256[] memory indices = new uint256[](4);
        uint24[] memory colours = new uint24[](4);
        indices[0] = 7;
        indices[1] = 8;
        indices[2] = 7;
        indices[3] = 7;
        colours[0] = 1;
        colours[1] = 2;
        colours[2] = 3;
        colours[3] = 4;
        uint256 total = 11 ether + 10 ether + 12.1 ether + 13.31 ether;
        uint256 beforeBalance = token.balanceOf(BOB);
        vm.expectCall(address(token), abi.encodeCall(IERC20.transferFrom, (BOB, address(wall), total)), 1);
        vm.expectEmit(true, true, false, true, address(wall));
        emit Painted(7, 1, BOB, 11 ether);
        vm.expectEmit(true, true, false, true, address(wall));
        emit Painted(8, 2, BOB, 10 ether);
        vm.expectEmit(true, true, false, true, address(wall));
        emit Painted(7, 3, BOB, 12.1 ether);
        vm.expectEmit(true, true, false, true, address(wall));
        emit Painted(7, 4, BOB, 13.31 ether);
        vm.prank(BOB);
        wall.paintBatch(indices, colours);
        assertEq(token.balanceOf(BOB), beforeBalance - total);
        assertEq(wall.withdrawable(ALICE), 5.5 ether);
        assertEq(wall.withdrawable(BOB), 6.05 ether + 6.655 ether);
        assertEq(wall.priceOf(7), 14.641 ether);
        assertEq(wall.priceOf(8), 11 ether);
        assertEq(uint8(wall.canvas()[23]), 4);
        _assertAccounting();
    }

    function test_batchAccepts64Pixels() public {
        uint256[] memory indices = new uint256[](64);
        uint24[] memory colours = new uint24[](64);
        for (uint256 i; i < 64; ++i) {
            indices[i] = 960 + i;
            colours[i] = uint24(i);
        }
        vm.prank(ALICE);
        wall.paintBatch(indices, colours);
        assertEq(token.balanceOf(DEAD), 640 ether);
        for (uint256 i = 960; i < 1024; ++i) {
            assertEq(wall.painterOf(i), ALICE);
            assertEq(wall.priceOf(i), 11 ether);
        }
        _assertAccounting();
    }

    function test_batchRejectsInvalidLengths() public {
        vm.expectRevert(PixelCanvas.InvalidBatchSize.selector);
        wall.paintBatch(new uint256[](0), new uint24[](0));
        vm.expectRevert(PixelCanvas.InvalidBatchSize.selector);
        wall.paintBatch(new uint256[](65), new uint24[](65));
        vm.expectRevert(PixelCanvas.LengthMismatch.selector);
        wall.paintBatch(new uint256[](2), new uint24[](1));
        vm.expectRevert(PixelCanvas.LengthMismatch.selector);
        wall.paintBatch(new uint256[](0), new uint24[](1));
    }

    function testFuzz_allIndexedEntryPointsRejectOutOfRange(uint256 index) public {
        index = bound(index, 1024, type(uint256).max);
        bytes memory reason = abi.encodeWithSelector(PixelCanvas.InvalidIndex.selector, index);
        vm.expectRevert(reason);
        wall.priceOf(index);
        vm.expectRevert(reason);
        wall.painterOf(index);
        vm.expectRevert(reason);
        wall.paint(index, 0);
    }

    function test_lateInvalidBatchIndexRollsBackEarlierPaintsAndCredits() public {
        _paint(ALICE, 0, 0x123456);
        bytes memory beforeCanvas = wall.canvas();
        uint256 beforeBalance = token.balanceOf(BOB);
        uint256[] memory indices = new uint256[](3);
        indices[2] = 1024;
        vm.expectRevert(abi.encodeWithSelector(PixelCanvas.InvalidIndex.selector, 1024));
        vm.prank(BOB);
        wall.paintBatch(indices, new uint24[](3));
        assertEq(wall.canvas(), beforeCanvas);
        assertEq(wall.painterOf(0), ALICE);
        assertEq(wall.priceOf(0), 11 ether);
        assertEq(token.balanceOf(BOB), beforeBalance);
        assertEq(token.balanceOf(DEAD), 10 ether);
        _assertAccounting();
    }

    function test_insufficientAllowanceRollsBackPaint() public {
        vm.prank(ALICE);
        token.approve(address(wall), 10 ether - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(wall), 10 ether - 1, 10 ether
            )
        );
        _paint(ALICE, 0, 1);
        assertEq(wall.canvas(), new bytes(3072));
        assertEq(wall.painterOf(0), address(0));
        assertEq(wall.priceOf(0), 10 ether);
        assertEq(token.balanceOf(DEAD), 0);
        _assertAccounting();
    }

    function test_batchRequiresFullCostEvenWhenCallerEarnsCredits() public {
        uint256[] memory indices = new uint256[](2);
        vm.prank(ALICE);
        token.approve(address(wall), 21 ether - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(wall), 21 ether - 1, 21 ether
            )
        );
        vm.prank(ALICE);
        wall.paintBatch(indices, new uint24[](2));
        assertEq(wall.priceOf(0), 10 ether);
        assertEq(wall.withdrawable(ALICE), 0);
        _assertAccounting();
    }

    function test_insufficientBalanceRollsBackPaint() public {
        address empty = address(0x1234);
        vm.prank(empty);
        token.approve(address(wall), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, empty, 0, 10 ether));
        _paint(empty, 0, 1);
        assertEq(wall.priceOf(0), 10 ether);
        assertEq(wall.painterOf(0), address(0));
        _assertAccounting();
    }

    function test_withdrawPaysOnlyCallerAndCannotPayTwice() public {
        _paint(ALICE, 0, 1);
        _paint(BOB, 0, 2);
        _paint(CAROL, 0, 3);
        uint256 beforeBalance = token.balanceOf(ALICE);
        vm.expectEmit(true, false, false, true, address(wall));
        emit Withdrawn(ALICE, 5.5 ether);
        vm.prank(ALICE);
        wall.withdraw();
        assertEq(token.balanceOf(ALICE), beforeBalance + 5.5 ether);
        assertEq(wall.withdrawable(ALICE), 0);
        assertEq(wall.withdrawable(BOB), 6.05 ether);
        vm.expectRevert(PixelCanvas.NothingToWithdraw.selector);
        vm.prank(ALICE);
        wall.withdraw();
        vm.prank(BOB);
        wall.withdraw();
        _assertAccounting();
        assertEq(token.balanceOf(address(wall)), 0);
    }

    function test_withdrawZeroReverts() public {
        vm.expectRevert(PixelCanvas.NothingToWithdraw.selector);
        vm.prank(ALICE);
        wall.withdraw();
    }

    function test_rejectsETHAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool direct,) = address(wall).call{value: 1}("");
        (bool paidPaint,) = address(wall).call{value: 1}(abi.encodeCall(PixelCanvas.paint, (0, 1)));
        (bool fallbackCall,) = address(wall).call(hex"abcdef12");
        assertFalse(direct);
        assertFalse(paidPaint);
        assertFalse(fallbackCall);
        assertEq(address(wall).balance, 0);
    }

    function test_unsolicitedTokenTransferIsSurplusAndDoesNotChangeCredits() public {
        _paint(ALICE, 0, 1);
        _paint(BOB, 0, 2);
        token.transfer(address(wall), 1 ether);
        assertEq(wall.withdrawable(ALICE), 5.5 ether);
        vm.prank(ALICE);
        wall.withdraw();
        assertEq(wall.withdrawable(ALICE), 0);
        assertEq(token.balanceOf(address(wall)), 1 ether);
    }
}
