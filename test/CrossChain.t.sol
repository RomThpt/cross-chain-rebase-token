// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
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
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

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
        rebaseTokenSepolia.grantMintAndBurnRole(address(rebaseTokenPoolSepolia));

        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(rebaseTokenSepolia));

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(rebaseTokenSepolia));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(rebaseTokenSepolia), address(rebaseTokenPoolSepolia));
        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipSimulator.getNetworkDetails(block.chainid);
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
        rebaseTokenArbSepolia.grantMintAndBurnRole(address(rebaseTokenPoolArbSepolia));

        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(rebaseTokenArbSepolia));

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(rebaseTokenArbSepolia));

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(rebaseTokenArbSepolia), address(rebaseTokenPoolArbSepolia));
        configureTokenPool(
            sepoliaFork,
            address(rebaseTokenPoolArbSepolia),
            uint64(sepoliaNetworkDetails.chainSelector),
            address(rebaseTokenPoolSepolia),
            address(rebaseTokenSepolia)
        );
        configureTokenPool(
            arbSepoliaFork,
            address(rebaseTokenPoolSepolia),
            uint64(arbSepoliaNetworkDetails.chainSelector),
            address(rebaseTokenPoolArbSepolia),
            address(rebaseTokenArbSepolia)
        );

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseTokenPool localPool,
        RebaseTokenPool remotePool,
        RebaseToken localToken,
        RebaseToken remoteToken,
        Vault localVault,
        Vault remoteVault
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(remotePool)),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        ccipSimulator.requestLinkFromFaucet(user, fee);

        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        vm.prank(user);
        IERC20(address(localToken)).approve(address(localPool), amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(user);

        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(user);

        assertEq(localBalanceBefore - localBalanceAfter, amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        ccipSimulator.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter - remoteBalanceBefore, amountToBridge);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }
}
