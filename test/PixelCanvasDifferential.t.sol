// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PixelCanvas} from "../src/PixelCanvas.sol";
import {CanvasFixture} from "./helpers/CanvasFixture.sol";

contract PixelCanvasDifferentialTest is CanvasFixture {
    PixelCanvas private singles;

    function setUp() public override {
        super.setUp();
        singles = new PixelCanvas(address(token));
        vm.prank(ALICE);
        token.approve(address(singles), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(singles), type(uint256).max);
    }

    function testFuzz_batchExactlyMatchesIndividualPaints(uint256 seed, uint8 rawLength) public {
        uint256 length = bound(rawLength, 1, 64);
        // Start with previous painters on half the possible indices.
        for (uint256 i; i < 4; ++i) {
            _paint(ALICE, i, 0);
            vm.prank(ALICE);
            singles.paint(i, 0);
        }
        uint256[] memory indices = new uint256[](length);
        uint24[] memory colours = new uint24[](length);
        for (uint256 i; i < length; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            indices[i] = seed % 8;
            colours[i] = uint24(seed);
        }
        _compare(indices, colours);
    }

    function test_duplicateBatchCrossingCapMatchesIndividualPaints() public {
        // Begin just below the cap, then cross it within a maximum-size duplicate batch.
        for (uint256 i; i < 120; ++i) {
            _paint(ALICE, 0, 0);
            vm.prank(ALICE);
            singles.paint(0, 0);
        }
        assertLt(wall.priceOf(0), 1_000_000 ether);
        _compare(new uint256[](64), new uint24[](64));
        assertEq(wall.priceOf(0), 1_000_000 ether);
    }

    function _compare(uint256[] memory indices, uint24[] memory colours) private {
        uint256 batchBalance = token.balanceOf(BOB);
        uint256 batchBurn = token.balanceOf(DEAD);
        vm.prank(BOB);
        wall.paintBatch(indices, colours);
        batchBalance -= token.balanceOf(BOB);
        batchBurn = token.balanceOf(DEAD) - batchBurn;

        uint256 singleBalance = token.balanceOf(BOB);
        uint256 singleBurn = token.balanceOf(DEAD);
        for (uint256 i; i < indices.length; ++i) {
            vm.prank(BOB);
            singles.paint(indices[i], colours[i]);
        }
        singleBalance -= token.balanceOf(BOB);
        singleBurn = token.balanceOf(DEAD) - singleBurn;

        assertEq(batchBalance, singleBalance, "full charge must match, including duplicates");
        assertEq(batchBurn, singleBurn, "burn rounding must match per entry");
        assertEq(wall.canvas(), singles.canvas());
        assertEq(wall.withdrawable(ALICE), singles.withdrawable(ALICE));
        assertEq(wall.withdrawable(BOB), singles.withdrawable(BOB));
        assertEq(token.balanceOf(address(wall)), token.balanceOf(address(singles)));
        assertEq(token.balanceOf(address(wall)), wall.withdrawable(ALICE) + wall.withdrawable(BOB));
        for (uint256 i; i < 8; ++i) {
            assertEq(wall.priceOf(i), singles.priceOf(i));
            assertEq(wall.painterOf(i), singles.painterOf(i));
        }
    }
}
