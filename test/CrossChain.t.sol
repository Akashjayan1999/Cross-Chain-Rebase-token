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
contract CrossChainTest is Test {
    address[] public allowlist = new address[](0);
    address public owner = makeAddr("owner");
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

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
    }
}