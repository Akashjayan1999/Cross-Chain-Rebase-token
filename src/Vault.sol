//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
contract Vault {
    //we need to pass the token address to the constructor
    //create a deposit function that mints tokens to the user equal to the amount of ETH the user has send
    //create a redeem function that burns tokens from the user and sends the user ETH
    //create a way to add rewards to the valut
    

     event Deposit(address indexed user, uint256 amount);
     event Redeem(address indexed user, uint256 amount);

     error Vault__RedeemFailed();


    IRebaseToken private immutable i_rebaseToken;
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }



    receive() external payable {
        
    }
 
    /**
     * @notice allows user to depost ETH into the valut and mint rebase tokens in returns
     */
    function deposit() external payable {
       // 1. we need to use the amount of ETH the user has sent to mint tokens to the user
       i_rebaseToken.mint(msg.sender, msg.value);
       emit Deposit(msg.sender, msg.value);

    }

     /**
     * @dev redeems rebase token for the underlying asset
     * @param _amount the amount being redeemed
     *
     */
    function redeem(uint256 _amount) external {
        //1.burn rge token from the user
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        // executes redeem of the underlying asset
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    
    function getRebaseToken() external view returns (address) {
        return address(i_rebaseToken);
    }
}