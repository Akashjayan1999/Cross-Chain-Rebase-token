// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {console, Test} from "forge-std/Test.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public user = makeAddr("user");
    address public owner = makeAddr("owner");


    function setUp() public {
        vm.startPrank(owner);

        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grandMintAndBurnRole(address(vault));
        (bool success,)=payable(address(vault)).call{value:1e18}("");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        // Deposit funds
        amount = bound(amount, 1e5, type(uint96).max);
       
       // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount); 
        vault.deposit{value: amount}();

         // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);

        // 3. warp the time and check the balance again

         vm.stopPrank();
    }
}