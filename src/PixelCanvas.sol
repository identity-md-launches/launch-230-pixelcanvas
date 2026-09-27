// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice A shared 32 by 32 canvas paid in the immutable PIXL launch token.
/// @dev Intended exclusively for the exact-transfer, non-rebasing LaunchToken.
contract PixelCanvas is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant PIXEL_COUNT = 1024;
    uint256 public constant MAX_BATCH_SIZE = 64;
    uint256 public constant INITIAL_PRICE = 10 ether;
    uint256 public constant MAX_PRICE = 1_000_000 ether;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable token;

    // Solidity packs ten uint24 colours per storage slot. No per-pixel bytes allocation.
    uint24[1024] private _colours;
    uint256[1024] private _prices;
    address[1024] private _painters;
    mapping(address account => uint256 amount) public withdrawable;

    error InvalidToken();
    error InvalidIndex(uint256 index);
    error InvalidBatchSize();
    error LengthMismatch();
    error NothingToWithdraw();

    event Painted(uint256 indexed index, uint24 colour, address indexed painter, uint256 price);
    event Withdrawn(address indexed account, uint256 amount);

    /// @param token_ The already-deployed PIXL LaunchToken; no initial funding is required.
    constructor(address token_) {
        if (token_.code.length == 0) revert InvalidToken();
        token = IERC20(token_);
    }

    /// @notice All pixels in index order, as consecutive three-byte RGB values.
    function canvas() external view returns (bytes memory colours) {
        colours = new bytes(PIXEL_COUNT * 3);
        for (uint256 i; i < PIXEL_COUNT; ++i) {
            bytes3 colour = bytes3(_colours[i]);
            uint256 offset = i * 3;
            colours[offset] = colour[0];
            colours[offset + 1] = colour[1];
            colours[offset + 2] = colour[2];
        }
    }

    function priceOf(uint256 index) public view returns (uint256) {
        _checkIndex(index);
        uint256 price = _prices[index];
        return price == 0 ? INITIAL_PRICE : price;
    }

    function painterOf(uint256 index) external view returns (address) {
        _checkIndex(index);
        return _painters[index];
    }

    /// @notice Pay the current price and replace one pixel, including your own.
    function paint(uint256 index, uint24 colour) external nonReentrant {
        (uint256 price, uint256 burnAmount) = _paint(index, colour);
        _collect(price, burnAmount);
    }

    /// @notice Paint 1–64 entries in order, charging duplicate indices at each successive price.
    function paintBatch(uint256[] calldata indices, uint24[] calldata colours) external nonReentrant {
        uint256 length = indices.length;
        if (length != colours.length) revert LengthMismatch();
        if (length == 0 || length > MAX_BATCH_SIZE) revert InvalidBatchSize();

        uint256 totalPrice;
        uint256 totalBurn;
        for (uint256 i; i < length; ++i) {
            (uint256 price, uint256 burnAmount) = _paint(indices[i], colours[i]);
            totalPrice += price;
            totalBurn += burnAmount;
        }
        _collect(totalPrice, totalBurn);
    }

    /// @notice Collect your entire credit. A failed token transfer restores the credit atomically.
    function withdraw() external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        withdrawable[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount);
        token.safeTransfer(msg.sender, amount);
    }

    function _paint(uint256 index, uint24 colour) private returns (uint256 price, uint256 burnAmount) {
        price = priceOf(index);
        address previousPainter = _painters[index];
        uint256 credit;
        if (previousPainter != address(0)) {
            credit = price / 2;
            withdrawable[previousPainter] += credit;
        }

        _colours[index] = colour;
        _painters[index] = msg.sender;
        // price is always <= MAX_PRICE, so multiplication cannot overflow.
        uint256 nextPrice = price * 11 / 10;
        _prices[index] = nextPrice > MAX_PRICE ? MAX_PRICE : nextPrice;
        emit Painted(index, colour, msg.sender, price);
        burnAmount = price - credit;
    }

    function _collect(uint256 price, uint256 burnAmount) private {
        // All accounting is settled before either external call; failure rolls everything back.
        token.safeTransferFrom(msg.sender, address(this), price);
        token.safeTransfer(BURN_ADDRESS, burnAmount);
    }

    function _checkIndex(uint256 index) private pure {
        if (index >= PIXEL_COUNT) revert InvalidIndex(index);
    }
}
