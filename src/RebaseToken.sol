// SDPX-Licence-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author RomThpt
 * @notice A cross-chain rebase token that incentivises users to depostit into a vault and gain interest in rewards
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate taht is the global interest rate at the time of their deposit
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 newInterestRate, uint256 currentInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamps;

    event InterestRateUpdated(uint256 newInterestRate);

    constructor(uint256 _initialInterestRate) ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to be set
     * @dev The new interest rate can only be lower than the current interest rate
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Implementation for setting a new interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(_newInterestRate, s_interestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /*
    * @notice Get the principal balance of a user (the amount of tokens actually minted to
    * @param _user The address of the user
    * @return The principal balance of the user
    * @dev This function returns the balance without accrued interest
    */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint rebase tokens to a user
     * @dev Internal function to mint tokens
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /*
    * @notice Burn rebase tokens from a user
    * @param _from The address to burn tokens from
    * @param _amount The amount of tokens to burn
    */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Get the balance of a user including accrued interest
     * @dev Override the balanceOf function to include accrued interest
     * @param _user The address of the user
     * @return The balance of the user including accrued interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //get the current pricipal balance (the number that have actually been minted to the user)
        // multiply the principal by (1 + interest rate * time elapsed / seconds in a year)
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /*
    * @notice Transfer rebase tokens from one user to another
    * @dev Override the transfer function to mint accrued interest before transferring
    * @param _to The address to transfer tokens to
    * @param _amount The amount of tokens to transfer
    * @return A boolean value indicating whether the operation succeeded
    * @notice This function mints accrued interest to the sender before transferring tokens
    */
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        // TODO: if the recipient has no balance, set their interest rate to the sender's interest rate but it should adapt and so on
        if (balanceOf(_to) == 0) {
            s_userInterestRates[_to] = s_userInterestRates[msg.sender];
        }
        return super.transfer(_to, _amount);
    }

    /**
     * @notice Transfer rebase tokens from one user to another on behalf of a third party
     * @dev Override the transferFrom function to mint accrued interest before transferring
     * @param _from The address to transfer tokens from
     * @param _to The address to transfer tokens to
     * @param _amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     * @notice This function mints accrued interest to both the sender and recipient before transferring tokens
     */
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRates[_to] = s_userInterestRates[_from];
        }
        return super.transferFrom(_from, _to, _amount);
    }

    /**
     * @notice Calculate the accumulated interest for a user since their last update
     * @dev Internal function to calculate accumulated interest
     * @param _user The address of the user
     * @return The accumulated interest multiplier
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // (principal amount) + principak * user interest rate * time elapsed

        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamps[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
        return linearInterest;
    }

    /**
     * @notice Mint accrued interest to a user since the last time they performed an action
     * @dev Internal function to mint accrued interest based on the user's interest rate
     * @param _user The address of the user to mint interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find the current balance of rebase token that have been minted to them -> pricipal
        uint256 previousPrincipal = super.balanceOf(_user);
        // (2) calculate their current balance including any interest. -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user (2) - (1) -> interest
        uint256 interestToMint = currentBalance - previousPrincipal;
        // set the users last updated timestamp to now
        s_userLastUpdatedTimestamps[_user] = block.timestamp;
        //call _mint to mint the tokens to the user
        if (interestToMint > 0) {
            _mint(_user, interestToMint);
        }
    }

    /*****GETTERS******/

    /**
     * @notice Get the current global interest rate
     * @return The current global interest rate
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    /**
     * @notice Get the current global interest rate
     * @return The current global interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
