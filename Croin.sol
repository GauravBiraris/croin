// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CroinTRC20.sol";

/// @title Croin Token
/// @notice A sustainable token with credit and ballotin functionality
//  Croin Version 20

contract Croin is CroinTRC20 {
    address public admin;
    address[] public minters;
    address[] public tickers;
    
    uint256[] private activeBallotinIds;
    mapping(uint256 => uint256[]) private ballotinToActiveCredits;

    bool private _paused;
    bool private _hanged;

    uint256 public quorumPercentage = 75;
    uint256 public feeRatio = 500;
    uint256 public minFeeAmount = 40 * 10**18;
    uint256 public membersShare = 8200;
    uint256 public tickerShare = 1500;
    uint256 public adminShare = 300;

    uint256 public nextCreditId = 1;
    uint256 public nextBallotinId = 1;

    struct Credit {
        uint256 timestamp;
        uint256 amount;
        uint256 fee;
        uint256 validity;
        address creditor;
        address debitor;        
        uint256 ballotinId;
        address[] trueVoters;
        address[] falseVoters;
    }

    mapping(uint256 => Credit) public credits;
    mapping(uint256 => address[]) public ballotins;

    event Paused();
    event Hanged();
    event Unhanged();
    event Unpaused();
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event TickerAdded(address indexed ticker);
    event TickerRemoved(address indexed ticker);
    event TrusteeAdded(uint256 indexed ballotinId, address indexed trustee);
    event TrusteeRemoved(uint256 indexed ballotinId, address indexed trustee);
    event CreditGenerated(uint256 indexed creditId, address indexed creditor, address indexed debitor, uint256 ballotinId, uint256 validity, uint256 amount, uint256 fee);
    event CreditDeleted(uint256 indexed creditId);
    event BallotinCreated(uint256 indexed ballotinId, uint256 totalActiveBallotins);
    event BallotinDeleted(uint256 indexed ballotinId, uint256 totalActiveBallotins);
    event DecisionTriggered(uint256 indexed creditId, bool decision, uint256 majorityVoters, uint256 trusteeShare, uint256 tickerShare);

    constructor() CroinTRC20("Croin", "CR") {
        admin = msg.sender;
        minters.push(msg.sender);
        _mint(msg.sender, 1_000_000_000 * 10**18);
    }

    modifier unHung() {
        require(!_hanged, "This functionality is hanged");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not the admin");
        _;
    }

    modifier onlyMinter() {
        require(isInArray(minters, msg.sender), "Caller is not a minter");
        _;
    }

    modifier onlyTicker() {
        require(isInArray(tickers, msg.sender), "Caller is not a ticker");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Contract is paused");
        _;
    }

    function isInArray(address[] storage array, address account) internal view returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == account) {
                return true;
            }
        }
        return false;
    }

    function hanged() public view returns (bool) {
        return _hanged;
    }

    function hang() external onlyAdmin {
        _hanged = true;
        emit Hanged();
    }

    function unhang() external onlyAdmin {
        _hanged = false;
        emit Unhanged();
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyAdmin {
        _paused = true;
        emit Paused();
    }

    function unpause() external onlyAdmin {
        _paused = false;
        emit Unpaused();
    }

    function addMinter(address minter) external onlyAdmin {
        require(!isInArray(minters, minter), "Already a minter");
        minters.push(minter);
        emit MinterAdded(minter);
    }

    function removeMinter(address minter) external onlyAdmin {
        for (uint i = 0; i < minters.length; i++) {
            if (minters[i] == minter) {
                minters[i] = minters[minters.length - 1];
                minters.pop();
                emit MinterRemoved(minter);
                return;
            }
        }
        revert("Not a minter");
    }

    function addTicker(address ticker) external onlyAdmin {
        require(!isInArray(tickers, ticker), "Already a ticker");
        tickers.push(ticker);
        emit TickerAdded(ticker);
    }

    function removeTicker(address ticker) external onlyAdmin {
        for (uint i = 0; i < tickers.length; i++) {
            if (tickers[i] == ticker) {
                tickers[i] = tickers[tickers.length - 1];
                tickers.pop();
                emit TickerRemoved(ticker);
                return;
            }
        }
        revert("Not a ticker");
    }

    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= 5_000_000_000 * 10**18, "Cap exceeded");
        _mint(to, amount);
    }

    function createBallotin(address initialTrustee) external onlyAdmin returns (uint256) {
        uint256 ballotinId = nextBallotinId++;
        ballotins[ballotinId].push(initialTrustee);
        activeBallotinIds.push(ballotinId);
        emit BallotinCreated(ballotinId, activeBallotinIds.length);
        emit TrusteeAdded(ballotinId, initialTrustee);
        return ballotinId;
    }

    function deleteBallotin(uint256 ballotinId) external onlyAdmin {
        require(ballotinId < nextBallotinId, "Invalid ballotin ID");
        require(ballotinToActiveCredits[ballotinId].length == 0, "Cannot delete ballotin with active credits");
        
        for (uint256 i = 0; i < activeBallotinIds.length; i++) {
            if (activeBallotinIds[i] == ballotinId) {
                activeBallotinIds[i] = activeBallotinIds[activeBallotinIds.length - 1];
                activeBallotinIds.pop();
                break;
            }
        }
        
        delete ballotins[ballotinId];
        emit BallotinDeleted(ballotinId, activeBallotinIds.length);
    }
    


    function getActiveBallotinIds() external view returns (uint256[] memory) {
        return activeBallotinIds;
    }

    function addTrustee(address trustee, uint256 ballotinId) external onlyAdmin {
        require(ballotinId < nextBallotinId, "Invalid ballotin ID");
        require(ballotins[ballotinId].length > 0, "Ballotin does not exist");
        require(!isTrusteeForBallotin(trustee, ballotinId), "Already a trustee for this ballotin");
        ballotins[ballotinId].push(trustee);
        emit TrusteeAdded(ballotinId, trustee);
    }

    function removeTrustee(address trustee, uint256 ballotinId) external onlyAdmin {
        require(ballotinId < nextBallotinId, "Invalid ballotin ID");
        require(ballotins[ballotinId].length > 0, "Ballotin does not exist");
        require(isTrusteeForBallotin(trustee, ballotinId), "Not a trustee for this ballotin");
        require(ballotins[ballotinId].length > 1, "Cannot remove the last trustee");
        
        address[] storage trustees = ballotins[ballotinId];
        for (uint256 i = 0; i < trustees.length; i++) {
            if (trustees[i] == trustee) {
                trustees[i] = trustees[trustees.length - 1];
                trustees.pop();
                emit TrusteeRemoved(ballotinId, trustee);
                break;
            }
        }
    }

    function isTrusteeForBallotin(address trustee, uint256 ballotinId) public view returns (bool) {
        address[] memory trustees = ballotins[ballotinId];
        for (uint i = 0; i < trustees.length; i++) {
            if (trustees[i] == trustee) {
                return true;
            }
        }
        return false;
    }

    function generateCredit(address debitor, uint256 amount, uint256 validity, uint256 ballotinId) external whenNotPaused returns (uint256) {
        require(isBallotinActive(ballotinId), "Ballotin is not active");

        uint256 fee = (amount * feeRatio) / 100000;

        fee = fee < minFeeAmount ? minFeeAmount : fee;

        require(amount + fee <= balanceOf(msg.sender), "Insufficient balance for credit and fee");

        uint256 creditId = nextCreditId++;
        Credit storage newCredit = credits[creditId];
        newCredit.timestamp = block.timestamp;
        newCredit.creditor = msg.sender;
        newCredit.debitor = debitor;
        newCredit.amount = amount;
        newCredit.fee = fee;
        newCredit.validity = validity;
        newCredit.ballotinId = ballotinId;

        ballotinToActiveCredits[ballotinId].push(creditId);

        _transfer(msg.sender, address(this), amount + fee);

        emit CreditGenerated(creditId, msg.sender, debitor, ballotinId, validity, amount, fee);
        return creditId;
    }

    function isBallotinActive(uint256 ballotinId) public view returns (bool) {
        for (uint256 i = 0; i < activeBallotinIds.length; i++) {
            if (activeBallotinIds[i] == ballotinId) {
                return true;
            }
        }
        return false;
    }

    function vote(uint256 creditId, bool decision) external {
        Credit storage credit = credits[creditId];
        require(isTrusteeForBallotin(msg.sender, credit.ballotinId), "Not a trustee for this ballotin OR The credit is inactive");
        
        for (uint128 i = 0; i < credit.trueVoters.length; i++) {
            require(credit.trueVoters[i] != msg.sender, "Already voted: In support");
        }
        for (uint128 i = 0; i < credit.falseVoters.length; i++) {
            require(credit.falseVoters[i] != msg.sender, "Already voted: Against");
        }
        
        if (decision) {
            credit.trueVoters.push(msg.sender);
        } else {
            credit.falseVoters.push(msg.sender);
        }
    }
    function removeCreditFromBallotin(uint256 creditId, uint256 ballotinId) private {
        uint256[] storage activeCredits = ballotinToActiveCredits[ballotinId];
        for (uint256 i = 0; i < activeCredits.length; i++) {
            if (activeCredits[i] == creditId) {
                activeCredits[i] = activeCredits[activeCredits.length - 1];
                activeCredits.pop();
                break;
            }
        }
    }

    function triggerDecision(uint256 creditId) external onlyTicker whenNotPaused {
        Credit storage credit = credits[creditId];
        address[] storage trustees = ballotins[credit.ballotinId];
        
        uint256 totalVotes = credit.trueVoters.length + credit.falseVoters.length;
        uint256 quorumThreshold = (trustees.length * quorumPercentage) / 100;

        require(block.timestamp <= credit.timestamp + credit.validity * 1 days, "Credit has expired");
        require(totalVotes >= quorumThreshold, "Not enough votes for ballotin decision");
        require(credit.trueVoters.length != credit.falseVoters.length, "Wait for one more vote, or check the credit details");

        bool decision = credit.trueVoters.length > credit.falseVoters.length;
        address[] memory majorityVoters = decision ? credit.trueVoters : credit.falseVoters;
        
        if (decision) {
            _transfer(address(this), credit.debitor, credit.amount);
        } else {
            _transfer(address(this), credit.creditor, credit.amount);
        }
        
        uint256 membersShareAmount = (credit.fee * membersShare) / 10000;
        uint256 tickerShareAmount = (credit.fee * tickerShare) / 10000;
        uint256 adminShareAmount = credit.fee - membersShareAmount - tickerShareAmount;
        
        if (majorityVoters.length > 0) {
            uint256 memberFee = membersShareAmount / majorityVoters.length;
            for (uint256 i = 0; i < majorityVoters.length; i++) {
                _transfer(address(this), majorityVoters[i], memberFee);
            }
        } else {
            adminShareAmount += membersShareAmount;
        }
        
        _transfer(address(this), msg.sender, tickerShareAmount);
        _transfer(address(this), admin, adminShareAmount);
        emit DecisionTriggered(
            creditId, 
            decision, 
            majorityVoters.length, 
            membersShareAmount, 
            tickerShareAmount
        );
        removeCreditFromBallotin(creditId, credit.ballotinId);
        delete credits[creditId];
        emit CreditDeleted(creditId);
    }

    function deleteExpiredCredits() external unHung {
        for (uint256 ballotinId = 1; ballotinId < nextBallotinId; ballotinId++) {
            uint256[] storage activeCredits = ballotinToActiveCredits[ballotinId];
            for (uint256 i = 0; i < activeCredits.length; i++) {
                uint256 creditId = activeCredits[i];
                Credit storage credit = credits[creditId];
                if (block.timestamp > credit.timestamp + credit.validity * 1 days) {
                    _transfer(address(this), credit.creditor, credit.amount);
                    _transfer(address(this), admin, credit.fee);
                    // Remove the credit from the active credits array
                    activeCredits[i] = activeCredits[activeCredits.length - 1];
                    activeCredits.pop();
                    delete credits[creditId];
                    emit CreditDeleted(creditId);
                    i--; // Adjust index as we've removed an element
                }
            }
        }
    }


    function changeQuorumRequirement(uint256 newQuorumPercentage) external onlyAdmin unHung {
        require(newQuorumPercentage > 0 && newQuorumPercentage <= 100, "Invalid quorum percentage");
        quorumPercentage = newQuorumPercentage;
    }

    function changeFeeDistributionRatio(uint256 newMembersShare, uint256 newTickerShare, uint256 newAdminShare) external onlyAdmin unHung {
        require(newMembersShare + newTickerShare + newAdminShare == 100, "Total must be 100");
        membersShare = newMembersShare;
        tickerShare = newTickerShare;
        adminShare = newAdminShare;
    }

    function changeFeeParameters(uint256 newFeeRatio, uint256 newMinFeeAmount) external onlyAdmin unHung {
        feeRatio = newFeeRatio;
        minFeeAmount = newMinFeeAmount;
    }

    function getCreditDetails(uint256 creditId) external view returns (
        uint256 timestamp,
        address creditor,
        address debitor,
        uint256 amount,
        uint256 fee,
        uint256 validity,
        uint256 ballotinId,
        uint256 trueVotes,
        uint256 falseVotes
    ) {
        Credit memory credit = credits[creditId];
        require(credit.creditor != address(0), "Credit does not exist");
        
        return (
            credit.timestamp,
            credit.creditor,
            credit.debitor,
            credit.amount,
            credit.fee,
            credit.validity,
            credit.ballotinId,
            credit.trueVoters.length,
            credit.falseVoters.length
        );
    }

    function getTrusteeBallotinIds(address trustee) public unHung view returns (uint256[] memory) {
        uint256[] memory ballotinIds = new uint256[](nextBallotinId - 1);
        uint256 count = 0;

        for (uint256 i = 1; i < nextBallotinId; i++) {
            if (isTrusteeForBallotin(trustee, i)) {
                ballotinIds[count] = i;
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ballotinIds[i];
        }

        return result;
    }

    function getBallotinTrusteesCount(uint256 ballotinId) external view returns (uint256) {
        return ballotins[ballotinId].length;
    }

    function getTickerAddresses() external view unHung returns (address[] memory) {
        return tickers;
    }

    function getMinterAddresses() external view unHung returns (address[] memory) {
        return minters;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(!_paused, "Token transfer while paused");
        super._beforeTokenTransfer(from, to, amount);
    }
}