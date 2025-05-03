//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {console, Test} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
contract CrossChainTest is Test {
    address[] public allowlist = new address[](0);
    address public owner = makeAddr("owner");
     address public user = makeAddr("user");
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
     uint256 public SEND_VALUE = 1e5;

    RebaseToken destRebaseToken;
    RebaseToken sourceRebaseToken;

    RebaseTokenPool destPool;
    RebaseTokenPool sourcePool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    Vault vault;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomarbSepolia;


    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryarbSepolia;

    function setUp() public {
       sepoliaFork = vm.createSelectFork("eth"); 
       arbSepoliaFork = vm.createFork("arb");

       ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
       vm.makePersistent(address(ccipLocalSimulatorFork));
        
       // 1. Deploy and configure on the source chain: Sepolia
        vm.startPrank(owner);
        sourceRebaseToken = new RebaseToken();
        console.log("source rebase token address");
        console.log(address(sourceRebaseToken));
        console.log("Deploying token pool on Sepolia");
        vault = new Vault(IRebaseToken(address(sourceRebaseToken)));
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        sourcePool = new RebaseTokenPool(
            IERC20(address(sourceRebaseToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // add rewards to the vault
        vm.deal(address(vault), 1e18);
        // Set pool on the token contract for permissions on Sepolia
        sourceRebaseToken.grandMintAndBurnRole(address(sourcePool));
        sourceRebaseToken.grandMintAndBurnRole(address(vault));

        // Claim role on Sepolia
        registryModuleOwnerCustomSepolia =
            RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sourceRebaseToken));
        
        // Accept role on Sepolia
        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistrySepolia.acceptAdminRole(address(sourceRebaseToken));
         // Link token to pool in the token admin registry on Sepolia
        tokenAdminRegistrySepolia.setPool(address(sourceRebaseToken), address(sourcePool));

        
        vm.stopPrank();

        //2. Deploy and configure on the destination chain: Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        destRebaseToken = new RebaseToken();
        console.log("dest rebase token address");
        console.log(address(destRebaseToken));
        // Deploy the token pool on Arbitrum
        console.log("Deploying token pool on Arbitrum");
        destPool = new RebaseTokenPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        destRebaseToken.grandMintAndBurnRole(address(destPool));
        // Claim role on Arbitrum
        registryModuleOwnerCustomarbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomarbSepolia.registerAdminViaOwner(address(destRebaseToken));
        
        // Accept role on Arbitrum
        tokenAdminRegistryarbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryarbSepolia.acceptAdminRole(address(destRebaseToken));
        // Link token to pool in the token admin registry on Arbitrum
        tokenAdminRegistryarbSepolia.setPool(address(destRebaseToken), address(destPool));

        
       
        vm.stopPrank();
        //Configure the token pool on Sepolia
         configureTokenPool(
            sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
        );
        //Configure the token pool on Arbitrum
        configureTokenPool(
            arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
        );
    }

        function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(remotePool));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            allowed:true,
            remotePoolAddress: remotePoolAddresses[0],
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
       // uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        localPool.applyChainUpdates(chains);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Create the message to send tokens cross-chain
        vm.selectFork(localFork);
        vm.startPrank(user);
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: "", // We don't need any extra args for this example
            feeToken: localNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        vm.stopPrank();
        // Give the user the fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            user, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );
        vm.startPrank(user);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        ); // Approve the fee
        // log the values before bridging
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(user);
        console.log("Local balance before bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); // Send the message
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(user);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);
        uint256 localUserInterstRate = localToken.getUserInterestRate(user);
        console.log("Local user interest rate: %d", localUserInterstRate);
        vm.stopPrank();

        vm.selectFork(remoteFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 900);
        // get initial balance on Arbitrum
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(user);
        console.log("Remote balance before bridge: %d", initialArbBalance);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteUserInterstRate = remoteToken.getUserInterestRate(user);
        console.log("Remote user interest rate: %d", remoteUserInterstRate);
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(user);
        assertEq(remoteUserInterstRate, localUserInterstRate);
        console.log("Remote balance after bridge: %d", destBalance);
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }


     function testBridgeAllTokens() public {
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        // Deposit to the vault and receive tokens
         Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
         // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
         vm.stopPrank();
         // bridge ALL TOKENS to the destination chain
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
     }


     function testBridgeAllTokensBack() public {
       
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge ALL TOKENS to the destination chain
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        console.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(user));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", destRebaseToken.balanceOf(user));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(user);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }

     function testBridgeTwice() public {
        
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge half tokens to the destination chain
        // bridge the tokens
        console.log("Bridging %d tokens (first bridging event)", SEND_VALUE / 2);
        bridgeTokens(
            SEND_VALUE / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
        // wait 1 hour for the interest to accrue
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        uint256 newSourceBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        // bridge the tokens
        console.log("Bridging %d tokens (second bridging event)", newSourceBalance);
        bridgeTokens(
            newSourceBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        // wait an hour for the tokens to accrue interest on the destination chain
        console.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(user));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", destRebaseToken.balanceOf(user));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(user);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }


  

}