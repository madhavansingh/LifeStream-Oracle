// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Remix-friendly OpenZeppelin imports (raw GitHub)
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.6/contracts/utils/Counters.sol";

contract LifeStreamOracle is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    struct Goal {
        uint256 id;
        address owner;
        string description;
        string category;
        uint256 stakeAmount;
        uint256 deadline;
        bool isCompleted;
        bool isVerified;
        uint256 difficulty; // 1-5 scale
        string evidenceURI;
        uint256 supportCount;
        mapping(address => bool) supporters;
    }

    struct Achievement {
        uint256 goalId;
        uint256 timestamp;
        uint256 difficulty;
        string category;
        string description;
    }

    // State variables
    // Make goals private because the struct contains a mapping (public auto-getter can't be created)
    mapping(uint256 => Goal) private goals;
    mapping(address => uint256[]) private userGoals;
    mapping(address => Achievement[]) private userAchievements;
    mapping(string => uint256) public categoryMultipliers;
    
    uint256 public nextGoalId = 1;
    uint256 public constant MIN_STAKE = 0.01 ether;
    uint256 public constant VERIFICATION_THRESHOLD = 3;
    
    // Events
    event GoalCreated(uint256 indexed goalId, address indexed owner, string description, uint256 stakeAmount);
    event GoalCompleted(uint256 indexed goalId, address indexed owner, string evidenceURI);
    event GoalVerified(uint256 indexed goalId, address indexed owner);
    event AchievementMinted(uint256 indexed tokenId, address indexed owner, uint256 goalId);
    event GoalSupported(uint256 indexed goalId, address indexed supporter);

    constructor() ERC721("LifeStream Achievement", "LSA") {
        // Initialize category multipliers (percentages)
        categoryMultipliers["fitness"] = 150;
        categoryMultipliers["education"] = 200;
        categoryMultipliers["career"] = 180;
        categoryMultipliers["creative"] = 160;
        categoryMultipliers["social"] = 140;

        // Start token IDs at 1
        _tokenIdCounter.reset();
    }

    /**
     * @dev Create a new life goal with stake
     */
    function createGoal(
        string memory _description,
        string memory _category,
        uint256 _deadline,
        uint256 _difficulty
    ) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake amount");
        require(_deadline > block.timestamp, "Deadline must be in future");
        require(_difficulty >= 1 && _difficulty <= 5, "Difficulty must be 1-5");
        require(bytes(_description).length > 0, "Description cannot be empty");

        uint256 goalId = nextGoalId++;
        
        // Initialize storage struct (mapping inside struct allowed in storage)
        Goal storage newGoal = goals[goalId];
        newGoal.id = goalId;
        newGoal.owner = msg.sender;
        newGoal.description = _description;
        newGoal.category = _category;
        newGoal.stakeAmount = msg.value;
        newGoal.deadline = _deadline;
        newGoal.difficulty = _difficulty;
        newGoal.isCompleted = false;
        newGoal.isVerified = false;
        newGoal.supportCount = 0;

        userGoals[msg.sender].push(goalId);

        emit GoalCreated(goalId, msg.sender, _description, msg.value);
    }

    /**
     * @dev Complete goal and submit evidence
     */
    function completeGoal(uint256 _goalId, string memory _evidenceURI) external {
        Goal storage goal = goals[_goalId];
        
        require(goal.owner == msg.sender, "Not goal owner");
        require(!goal.isCompleted, "Goal already completed");
        require(block.timestamp <= goal.deadline, "Goal deadline passed");
        require(bytes(_evidenceURI).length > 0, "Evidence URI required");

        goal.isCompleted = true;
        goal.evidenceURI = _evidenceURI;

        emit GoalCompleted(_goalId, msg.sender, _evidenceURI);
    }

    /**
     * @dev Community verification and achievement minting
     */
    function verifyAndMintAchievement(uint256 _goalId) external {
        Goal storage goal = goals[_goalId];
        
        require(goal.isCompleted, "Goal not completed yet");
        require(!goal.isVerified, "Goal already verified");
        require(msg.sender != goal.owner, "Owner cannot verify own goal");
        require(!goal.supporters[msg.sender], "Already supported this goal");

        goal.supporters[msg.sender] = true;
        goal.supportCount++;

        emit GoalSupported(_goalId, msg.sender);

        // If verification threshold reached, verify and mint achievement
        if (goal.supportCount >= VERIFICATION_THRESHOLD) {
            goal.isVerified = true;
            
            // Mint Achievement NFT with 1-based token IDs
            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _safeMint(goal.owner, tokenId);

            // Store achievement data
            Achievement memory newAchievement = Achievement({
                goalId: _goalId,
                timestamp: block.timestamp,
                difficulty: goal.difficulty,
                category: goal.category,
                description: goal.description
            });
            
            userAchievements[goal.owner].push(newAchievement);

            // Calculate reward with category multiplier (default 100%)
            uint256 baseReward = goal.stakeAmount;
            uint256 multiplier = categoryMultipliers[goal.category] == 0 ? 100 : categoryMultipliers[goal.category];
            // Compute as (base * multiplier * difficulty) / 100 to interpret multiplier as percentage
            uint256 totalReward = (baseReward * multiplier * goal.difficulty) / 100;

            // Cap transfer to contract balance
            uint256 payout = totalReward > address(this).balance ? address(this).balance : totalReward;
            if (payout > 0) {
                payable(goal.owner).transfer(payout);
            }

            emit GoalVerified(_goalId, goal.owner);
            emit AchievementMinted(tokenId, goal.owner, _goalId);
        }
    }

    /**
     * @dev Get user's goals (IDs)
     */
    function getUserGoals(address _user) external view returns (uint256[] memory) {
        return userGoals[_user];
    }

    /**
     * @dev Get user's achievements count
     */
    function getUserAchievementCount(address _user) external view returns (uint256) {
        return userAchievements[_user].length;
    }

    /**
     * @dev Get a specific achievement for a user by index
     */
    function getUserAchievement(address _user, uint256 _index) external view returns (
        uint256 goalId,
        uint256 timestamp,
        uint256 difficulty,
        string memory category,
        string memory description
    ) {
        require(_index < userAchievements[_user].length, "Index out of bounds");
        Achievement storage a = userAchievements[_user][_index];
        return (a.goalId, a.timestamp, a.difficulty, a.category, a.description);
    }

    /**
     * @dev Get goal details (excluding supporters mapping)
     */
    function getGoalDetails(uint256 _goalId) external view returns (
        address owner,
        string memory description,
        string memory category,
        uint256 stakeAmount,
        uint256 deadline,
        bool isCompleted,
        bool isVerified,
        uint256 difficulty,
        string memory evidenceURI,
        uint256 supportCount
    ) {
        Goal storage goal = goals[_goalId];
        return (
            goal.owner,
            goal.description,
            goal.category,
            goal.stakeAmount,
            goal.deadline,
            goal.isCompleted,
            goal.isVerified,
            goal.difficulty,
            goal.evidenceURI,
            goal.supportCount
        );
    }

    /**
     * @dev Check if user has supported a goal
     */
    function hasSupported(uint256 _goalId, address _supporter) external view returns (bool) {
        return goals[_goalId].supporters[_supporter];
    }

    /**
     * @dev Emergency withdrawal for failed goals past deadline
     */
    function withdrawFailedGoal(uint256 _goalId) external {
        Goal storage goal = goals[_goalId];
        
        require(goal.owner == msg.sender, "Not goal owner");
        require(!goal.isCompleted, "Goal was completed");
        require(block.timestamp > goal.deadline, "Deadline not passed");
        require(goal.stakeAmount > 0, "Already withdrawn");

        uint256 penaltyAmount = (goal.stakeAmount * 20) / 100; // 20% penalty
        uint256 refundAmount = goal.stakeAmount - penaltyAmount;
        
        // Clear stake to prevent re-entrancy double-withdraw (state change first)
        goal.stakeAmount = 0;

        if (refundAmount > 0) {
            payable(msg.sender).transfer(refundAmount);
        }
        // penaltyAmount remains in contract balance as intended
    }

    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Owner can update category multipliers
     */
    function updateCategoryMultiplier(string memory _category, uint256 _multiplier) external onlyOwner {
        categoryMultipliers[_category] = _multiplier;
    }

    /**
     * @dev Fallback function to receive Ether
     */
    receive() external payable {}
}

