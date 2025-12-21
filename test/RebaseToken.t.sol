// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        vm.deal(owner, 10 ether);
        rebaseToken = new RebaseToken(5e10);
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");
        vm.stopPrank();
    }

    function addRewardstoVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testInitialInterestRate() public {
        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, 5e10);
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        console.log("Depositing amount:", amount);
        vault.deposit{value: amount}();
        vm.warp(block.timestamp + 365 days);
        uint256 balance = rebaseToken.balanceOf(user);
        uint256 interestRate = 5e10;
        uint256 timeElapsed = 365 days; // in seconds
        uint256 expectedBalance = amount + (amount * interestRate * timeElapsed) / 1e18;
        console.log("Balance after 1 year:", balance);
        console.log("Expected balance:", expectedBalance);
        assertApproxEqAbs(balance, expectedBalance, 1); // Allow small margin of error
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);

        vm.stopPrank();
    }

    function testRedeemAfterTime(uint256 amount, uint256 time) public {
        amount = bound(amount, 1e5, type(uint96).max);
        time = bound(time, 1 days, type(uint96).max);

        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        uint256 balanceBefore = rebaseToken.balanceOf(user);
        assertEq(balanceBefore, amount);

        vm.warp(block.timestamp + time);
        uint256 balanceAfterTime = rebaseToken.balanceOf(user);
        assertGt(balanceAfterTime, balanceBefore);

        vm.prank(owner);
        vm.deal(owner, balanceAfterTime - amount);
        addRewardstoVault(balanceAfterTime - amount);

        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 balanceAfter = rebaseToken.balanceOf(user);
        assertEq(balanceAfter, 0);

        uint256 ethBalance = address(user).balance;
        assertEq(balanceAfterTime, ethBalance);
        assertGt(ethBalance, amount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        address recipient = makeAddr("recipient");
        vm.prank(user);
        rebaseToken.transfer(recipient, amountToSend);
        assertEq(rebaseToken.balanceOf(user), amount - amountToSend);
        assertEq(rebaseToken.balanceOf(recipient), amountToSend);

        assertEq(rebaseToken.getUserInterestRate(address(user)), 5e10);
        assertEq(rebaseToken.getUserInterestRate(address(recipient)), 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 newRate) public {
        newRate = bound(newRate, 1e10, type(uint96).max);
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newRate);
    }

    function testCannotCallMintAndBurn(address to, uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        uint256 interestRate = rebaseToken.getInterestRate();

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(to, amount, interestRate);

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(to, amount);
    }

    function testPricipalAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        vm.warp(block.timestamp + 180 days);
        uint256 principal = rebaseToken.principalBalanceOf(user);
        assertEq(principal, amount);
        vm.stopPrank();
    }
}
