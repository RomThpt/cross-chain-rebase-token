// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokenScript is Script {
    function run(
        address routerAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        address receiverAddress,
        uint256 amount,
        address linkTokenAddress
    ) public {
        vm.startBroadcast();
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amount});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);

        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        IERC20(tokenToSendAddress).approve(routerAddress, amount);

        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
