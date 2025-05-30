//SPDX-LIcense-Identifier: MIT
pragma solidity ^0.8.12;

import {TokenPool} from "@ccip/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
contract RebaseTokenPool is TokenPool {
    constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router) 
    TokenPool(token, allowlist, rmnProxy, router){

    }


 function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) external returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut){
     _validateLockOrBurn(lockOrBurnIn);

     // Burn the tokens on the source chain. This returns their userAccumulatedInterest before the tokens were burned (in case all tokens were burned, we don't want to send 0 cross-chain)
      // address reciever = abi.decode(lockOrBurnIn.receiver, (address));
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
      //uint256 currentInterestRate = IRebaseToken(address(i_token)).getInterestRate();
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
      
       lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
  
  } 

 function releaseOrMint(
    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) external returns (Pool.ReleaseOrMintOutV1 memory){
    _validateReleaseOrMint(releaseOrMintIn);

     (uint256 userInterestRate) = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
      // Mint rebasing tokens to the receiver on the destination chain
        // This will also mint any interest that has accrued since the last time the user's balance was updated.
      address receiver = releaseOrMintIn.receiver;
      IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount, userInterestRate);
     
      return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
  }  
}

