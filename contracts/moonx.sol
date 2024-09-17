// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IReputationContract {
    function reputation(address user) external view returns (uint256);
}

contract DecentralLearning is Ownable, Pausable {
    IReputationContract public reputationContract;

    uint256 public constant WATCH_THRESHOLD = 0;
    uint256 public constant ENROLL_THRESHOLD = 5;
    uint256 public constant POST_THRESHOLD = 5;
    uint256 public constant STUDENT_REWARD_AMOUNT = 10 ether; // 10 MAND tokens
    uint256 public constant CREATOR_REWARD_AMOUNT = 1 ether; // 1 MAND token per passed student
    uint256 public constant platformTX = 0.75 ether; // 0.75 MAND tokens

    uint256 public accumulatedFees;

    struct Course {
        address creator;
        string metadataURI;
        bool approved;
        uint256 passedStudents;
        uint256 creatorBalance;
        uint256 totalEnrolled;
    }

    struct Quiz {
        uint256 courseId;
        string question;
        string optionA;
        string optionB;
        string optionC;
        string optionD;
        bytes32 correctAnswerHash;
    }

    struct Enrollment {
        bool isEnrolled;
        uint8 attemptCount;
        bool hasPassed;
        uint256 quizBalance;
    }

    mapping(uint256 => Course) public courses;
    mapping(address => mapping(uint256 => Enrollment)) public enrollments;
    mapping(uint256 => Quiz[]) public courseQuizzes;
    uint256 public courseCount;

    event CourseCreated(uint256 indexed courseId, address indexed creator);
    event CourseApproved(uint256 indexed courseId);
    event QuizCreated(uint256 indexed courseId, uint256 quizId);
    event UserEnrolled(uint256 indexed courseId, address indexed user);
    event QuizAttempted(uint256 indexed courseId, address indexed user, bool passed);
    event RewardClaimed(uint256 indexed courseId, address indexed user, uint256 amount);
    event CreatorRewardClaimed(uint256 indexed courseId, address indexed creator, uint256 amount);
    event CreatorWithdrawal(uint256 indexed courseId, address indexed creator, uint256 amount);
    event GasFeesWithdrawn(uint256 amount);

    constructor(address _reputationContract) Ownable(msg.sender) {
        reputationContract = IReputationContract(_reputationContract);
    }

    modifier collectTX() {
        require(msg.value >= platformTX, "Insufficient gas fee");
        accumulatedFees += platformTX;
        uint256 excess = msg.value - platformTX;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }
        _;
    }

    function createCourse(string memory _metadataURI, Quiz[] memory _quizzes) external payable whenNotPaused collectTX {
        require(reputationContract.reputation(msg.sender) >= POST_THRESHOLD, "Insufficient reputation to create course");
        uint256 courseId = courseCount++;
        courses[courseId] = Course(msg.sender, _metadataURI, false, 0, 0, 0);
        
        for (uint256 i = 0; i < _quizzes.length; i++) {
            courseQuizzes[courseId].push(_quizzes[i]);
        }
        
        emit CourseCreated(courseId, msg.sender);
    }

    function approveCourse(uint256 _courseId) external onlyOwner {
        require(!courses[_courseId].approved, "Course already approved");
        courses[_courseId].approved = true;
        emit CourseApproved(_courseId);
    }

    function enrollInCourse(uint256 _courseId) external payable whenNotPaused collectTX {
        require(reputationContract.reputation(msg.sender) >= ENROLL_THRESHOLD, "Insufficient reputation to enroll");
        require(courses[_courseId].approved, "Course not approved");
        require(!enrollments[msg.sender][_courseId].isEnrolled, "Already enrolled");

        enrollments[msg.sender][_courseId].isEnrolled = true;
        courses[_courseId].totalEnrolled++;
        emit UserEnrolled(_courseId, msg.sender);
    }

    function attemptQuiz(uint256 _courseId, string[] memory _answers) external payable  {
        Enrollment storage enrollment = enrollments[msg.sender][_courseId];
        require(enrollment.isEnrolled, "User not enrolled in this course");
        require(enrollment.attemptCount < 2, "Maximum attempts reached");

        enrollment.attemptCount++;
        Quiz[] memory quizzes = courseQuizzes[_courseId];
        require(_answers.length == quizzes.length, "Answer count mismatch");

        bool passed = true;

        for (uint256 i = 0; i < quizzes.length; i++) {
            if (keccak256(abi.encodePacked(_answers[i])) != quizzes[i].correctAnswerHash) {
                passed = false;
                break;
            }
        }

        if (passed && !enrollment.hasPassed) {
            enrollment.hasPassed = true;
            enrollment.quizBalance += STUDENT_REWARD_AMOUNT;
            courses[_courseId].passedStudents++;
            courses[_courseId].creatorBalance += CREATOR_REWARD_AMOUNT;
        }

        emit QuizAttempted(_courseId, msg.sender, passed);
    }

    function claimStudentReward(uint256 _courseId) external payable whenNotPaused collectTX {
        Enrollment storage enrollment = enrollments[msg.sender][_courseId];
        require(enrollment.quizBalance > 0, "No rewards to claim");

        uint256 rewardAmount = enrollment.quizBalance;
        enrollment.quizBalance = 0;

        (bool success, ) = payable(msg.sender).call{value: rewardAmount}("");
        require(success, "Failed to send MAND");

        emit RewardClaimed(_courseId, msg.sender, rewardAmount);
    }

    function claimCreatorReward(uint256 _courseId) external payable whenNotPaused collectTX {
        Course storage course = courses[_courseId];
        require(msg.sender == course.creator, "Only course creator can claim reward");
        require(course.creatorBalance > 0, "No rewards to claim");

        uint256 rewardAmount = course.creatorBalance;
        course.creatorBalance = 0;

        (bool success, ) = payable(msg.sender).call{value: rewardAmount}("");
        require(success, "Failed to send MAND");

        emit CreatorRewardClaimed(_courseId, msg.sender, rewardAmount);
    }

    function withdrawPlatformTX() external onlyOwner {
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Failed to withdraw gas fees");

        emit GasFeesWithdrawn(amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateReputationContract(address _newReputationContract) external onlyOwner {
        reputationContract = IReputationContract(_newReputationContract);
    }

    receive() external payable {}
}