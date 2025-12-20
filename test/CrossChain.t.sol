// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {
    RegistryModuleOwnerCustom
} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipSimulator;

    RebaseToken private rebaseTokenSepolia;
    RebaseTokenPool private rebaseTokenPoolSepolia;
    Vault private vaultSepolia;
    RebaseToken private rebaseTokenArbSepolia;
    RebaseTokenPool private rebaseTokenPoolArbSepolia;
    Vault private vaultArbSepolia;

    Register.NetworkDetails public sepoliaNetworkDetails;
    Register.NetworkDetails public arbSepoliaNetworkDetails;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork(vm.envString("arb-sepolia"));
        ccipSimulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipSimulator));

        vm.startPrank(owner);
        vm.deal(owner, 10 ether);
        // Deploy on Sepolia
        vm.selectFork(sepoliaFork);
        sepoliaNetworkDetails = ccipSimulator.getNetworkDetails(block.chainid);
        rebaseTokenSepolia = new RebaseToken(5e10);
        vaultSepolia = new Vault(IRebaseToken(address(rebaseTokenSepolia)));
        rebaseTokenPoolSepolia = new RebaseTokenPool(
            IERC20(address(rebaseTokenSepolia)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        rebaseTokenSepolia.grantMintAndBurnRole(address(vaultSepolia));
        rebaseTokenArbSepolia.grantMintAndBurnRole(address(rebaseTokenPoolSepolia));

        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(rebaseTokenSepolia));

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(rebaseTokenSepolia));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(rebaseTokenSepolia), address(vaultSepolia));

        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        vm.deal(owner, 10 ether);
        // Deploy on Arbitrum Sepolia
        rebaseTokenArbSepolia = new RebaseToken(5e10);
        vaultArbSepolia = new Vault(IRebaseToken(address(rebaseTokenArbSepolia)));
        rebaseTokenPoolArbSepolia = new RebaseTokenPool(
            IERC20(address(rebaseTokenArbSepolia)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        rebaseTokenArbSepolia.grantMintAndBurnRole(address(vaultArbSepolia));
        rebaseTokenSepolia.grantMintAndBurnRole(address(rebaseTokenPoolArbSepolia));

        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(rebaseTokenArbSepolia));

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(rebaseTokenArbSepolia));

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(rebaseTokenArbSepolia), address(vaultArbSepolia));

        vm.stopPrank();
    }
}
