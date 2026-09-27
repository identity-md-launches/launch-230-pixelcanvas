// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken private token;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Pixel Wall");
        assertEq(token.symbol(), "PIXL");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function test_factoryReceivesSupplyWithoutAnOwnerRole() public {
        vm.prank(ALICE);
        LaunchToken other = new LaunchToken();
        assertEq(other.balanceOf(ALICE), 1e27);
        assertEq(other.balanceOf(address(this)), 0);
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, 1e27);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), 1e27 - amount);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_approveAndTransferFromSpendExactAllowance() public {
        token.approve(ALICE, 15 ether);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 12 ether));
        assertEq(token.allowance(address(this), ALICE), 3 ether);
        assertEq(token.balanceOf(BOB), 12 ether);
        assertEq(token.balanceOf(address(this)), 1e27 - 12 ether);
    }

    function test_infiniteAllowanceIsPreserved() public {
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1 ether);
        assertEq(token.allowance(address(this), ALICE), type(uint256).max);
    }

    function test_transferWithoutBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_noMintOrAdministrativeSelectors() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1e27));
            (bool deployerSuccess,) = address(token).call(data);
            vm.prank(ALICE);
            (bool otherSuccess,) = address(token).call(data);
            assertFalse(deployerSuccess);
            assertFalse(otherSuccess);
        }
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }
}
