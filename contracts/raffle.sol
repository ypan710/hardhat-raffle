// Raffle

// Enter the lottery

// Pick a random winner (verifiably random)

// Winner to be selected every X minutes -> completely automated

// Chainlink oracle -> randomness, automated execution (Chainlink Keeper)

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol';
import '@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol';
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

error Raffle__NotEnoughETHEntered();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

/** @title a sample Raffle Contract
 *  @author Yongjian
 *  @notice This contract is for creating an untamperable decentralized smart contract 
 *  @dev This implements Chainlink VRF V2 amd Chainlink Keepers
 */ 
contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface{

    enum RaffleState {OPEN, CALCULATING } // 0 = OPEN, 1 = CALCULATING

    // State variables
    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_keyHash;
    uint64 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;

    // Lottery variables
    address private s_recentWinner;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    uint256 private i_interval;

    // Events
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    // Functions
    constructor(
        address vrfCoordinatorV2, 
        uint256 entranceFee, 
        bytes32 keyHash, 
        uint64 subscriptionId, 
        uint32 callbackGasLimit,
        uint256 interval) 
        VRFConsumerBaseV2(vrfCoordinatorV2){
        i_entranceFee = entranceFee;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState  = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    function enterRaffle() payable public {
       if (msg.value < i_entranceFee) {
        revert Raffle__NotEnoughETHEntered();
       }
       if (s_raffleState != RaffleState.OPEN) {
        revert Raffle__NotOpen();
       }
       s_players.push(payable(msg.sender));
       emit RaffleEnter(msg.sender);
    }

    function getEntranceFee() public view returns(uint256){
        return i_entranceFee;
    }

    function getPlayer(uint256 index) public view returns(address payable){
        return s_players[index];
    }

    function getRaffleState() public view returns(RaffleState) {
        return s_raffleState;
    }

    function getNumberOfWords() public pure returns (uint32) {
        return NUM_WORDS;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLastestTimestamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function requestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

     function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function requestRandomWinner() external {
        // request the random number
        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);  // reset player address array once winner has been selected
        s_lastTimeStamp = block.timestamp; // reset time stamp once winner has been selected
        (bool success, ) = recentWinner.call{value: address(this).balance}(""); // transfer raffle balance to winner
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function checkUpkeep(bytes memory /* checkData */) public view override returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = (block.timestamp - s_lastTimeStamp) > i_interval;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded){
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
        // We don't use the performData in this example. The performData is generated by the Automation Node's call to your checkUpkeep function
    }
}