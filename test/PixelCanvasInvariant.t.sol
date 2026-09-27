// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {PixelCanvas} from "../src/PixelCanvas.sol";

/// @dev A separate model uses p + floor(p / 10) and a signed-free credit ledger.
/// The 16 hot pixels intentionally accumulate many repaints and reach the cap.
contract CanvasHandler is Test {
    LaunchToken public immutable token;
    PixelCanvas public immutable wall;
    address[4] public actors;
    uint256[16] public modelPrices;
    address[16] public modelPainters;
    uint24[16] public modelColours;
    mapping(address => uint256) public modelCredits;
    uint256 public modelBurned;
    uint256 public modelPaid;
    uint256 public modelWithdrawn;
    uint256 public successfulPaints;

    constructor(LaunchToken token_, PixelCanvas wall_) {
        token = token_;
        wall = wall_;
        for (uint256 i; i < 4; ++i) {
            actors[i] = address(uint160(0x1000 + i));
            vm.prank(actors[i]);
            token.approve(address(wall), type(uint256).max);
        }
        for (uint256 i; i < 16; ++i) {
            modelPrices[i] = 10 ether;
        }
    }

    function paint(uint256 actorSeed, uint256 indexSeed, uint24 colour) external {
        address actor = actors[actorSeed % 4];
        uint256 index = indexSeed % 16;
        if (token.balanceOf(actor) < modelPrices[index]) return;
        vm.prank(actor);
        wall.paint(index, colour);
        _modelPaint(actor, index, colour);
    }

    function paintBatch(uint256 actorSeed, uint256 seed, uint8 rawLength) external {
        address actor = actors[actorSeed % 4];
        uint256 length = bound(rawLength, 1, 64);
        uint256[] memory indices = new uint256[](length);
        uint24[] memory colours = new uint24[](length);
        uint256[16] memory quotes = modelPrices;
        uint256 total;
        for (uint256 i; i < length; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 index = seed % 16;
            indices[i] = index;
            colours[i] = uint24(seed);
            total += quotes[index];
            quotes[index] = _next(quotes[index]);
        }
        if (token.balanceOf(actor) < total) return;
        vm.prank(actor);
        wall.paintBatch(indices, colours);
        for (uint256 i; i < length; ++i) {
            _modelPaint(actor, indices[i], colours[i]);
        }
    }

    function withdraw(uint256 actorSeed) external {
        address actor = actors[actorSeed % 4];
        uint256 amount = modelCredits[actor];
        if (amount == 0) return;
        vm.prank(actor);
        wall.withdraw();
        modelCredits[actor] = 0;
        modelWithdrawn += amount;
    }

    function _modelPaint(address actor, uint256 index, uint24 colour) private {
        uint256 price = modelPrices[index];
        address previous = modelPainters[index];
        uint256 credit = previous == address(0) ? 0 : price / 2;
        modelCredits[previous] += credit;
        modelBurned += price - credit;
        modelPaid += price;
        modelPainters[index] = actor;
        modelPrices[index] = _next(price);
        modelColours[index] = colour;
        ++successfulPaints;
    }

    function _next(uint256 price) private pure returns (uint256) {
        uint256 grown = price + price / 10;
        return grown < 1_000_000 ether ? grown : 1_000_000 ether;
    }
}

contract PixelCanvasInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    PixelCanvas private wall;
    CanvasHandler private handler;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new LaunchToken();
        wall = new PixelCanvas(address(token));
        handler = new CanvasHandler(token, wall);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), 250_000_000 ether);
        }
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = CanvasHandler.paint.selector;
        selectors[1] = CanvasHandler.paintBatch.selector;
        selectors[2] = CanvasHandler.withdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_balanceEqualsCreditsAndEveryPaymentIsAccountedFor() public view {
        uint256 credits;
        uint256 playerBalances;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(wall.withdrawable(actor), handler.modelCredits(actor));
            credits += wall.withdrawable(actor);
            playerBalances += token.balanceOf(actor);
        }
        assertEq(token.balanceOf(address(wall)), credits);
        assertEq(token.balanceOf(DEAD), handler.modelBurned());
        assertEq(handler.modelPaid(), handler.modelBurned() + credits + handler.modelWithdrawn());
        assertEq(playerBalances + credits + token.balanceOf(DEAD), 1e27);
        assertEq(token.totalSupply(), 1e27);
    }

    function invariant_pricesAndPaintersMatchSequentialModel() public view {
        for (uint256 i; i < 16; ++i) {
            assertEq(wall.priceOf(i), handler.modelPrices(i));
            assertEq(wall.painterOf(i), handler.modelPainters(i));
            assertGe(wall.priceOf(i), 10 ether);
            assertLe(wall.priceOf(i), 1_000_000 ether);
        }
    }

    function afterInvariant() public {
        bytes memory colours = wall.canvas();
        assertEq(colours.length, 3072);
        for (uint256 i; i < 16; ++i) {
            uint24 actual = (uint24(uint8(colours[i * 3])) << 16) | (uint24(uint8(colours[i * 3 + 1])) << 8)
                | uint24(uint8(colours[i * 3 + 2]));
            assertEq(actual, handler.modelColours(i));
        }
        for (uint256 i; i < 4; ++i) {
            handler.withdraw(i);
        }
        assertEq(token.balanceOf(address(wall)), 0, "all liabilities can be paid");
    }
}
