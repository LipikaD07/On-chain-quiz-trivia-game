// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract QuizGame {
    address public owner;
    uint256 public gameCounter;
    uint256 public constant ENTRY_FEE = 0.01 ether;
    uint256 public constant REWARD_AMOUNT = 0.015 ether;
    
    struct Quiz {
        uint256 gameId;
        string question;
        string[] options;
        uint256 correctAnswer; // Index of correct answer (0-3)
        uint256 timeLimit; // Time limit in seconds
        uint256 startTime;
        bool isActive;
        address[] participants;
        address winner;
        uint256 prizePool;
    }
    
    struct Player {
        uint256 totalGamesPlayed;
        uint256 totalWins;
        uint256 totalEarnings;
    }
    
    mapping(uint256 => Quiz) public quizzes;
    mapping(address => Player) public players;
    mapping(uint256 => mapping(address => bool)) public hasAnswered;
    mapping(uint256 => mapping(address => uint256)) public playerAnswers;
    
    event QuizCreated(uint256 indexed gameId, string question, uint256 timeLimit);
    event PlayerJoined(uint256 indexed gameId, address indexed player);
    event AnswerSubmitted(uint256 indexed gameId, address indexed player, uint256 answer);
    event QuizEnded(uint256 indexed gameId, address indexed winner, uint256 prize);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier gameExists(uint256 _gameId) {
        require(_gameId < gameCounter, "Game does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Function 1: Create a new quiz (only owner)
    function createQuiz(
        string memory _question,
        string[] memory _options,
        uint256 _correctAnswer,
        uint256 _timeLimitSeconds
    ) external onlyOwner {
        require(_options.length == 4, "Must have exactly 4 options");
        require(_correctAnswer < 4, "Correct answer index must be 0-3");
        require(_timeLimitSeconds > 0, "Time limit must be greater than 0");
        
        Quiz storage newQuiz = quizzes[gameCounter];
        newQuiz.gameId = gameCounter;
        newQuiz.question = _question;
        newQuiz.options = _options;
        newQuiz.correctAnswer = _correctAnswer;
        newQuiz.timeLimit = _timeLimitSeconds;
        newQuiz.startTime = block.timestamp;
        newQuiz.isActive = true;
        newQuiz.prizePool = 0;
        
        emit QuizCreated(gameCounter, _question, _timeLimitSeconds);
        gameCounter++;
    }
    
    // Function 2: Join a quiz by paying entry fee
    function joinQuiz(uint256 _gameId) external payable gameExists(_gameId) {
        Quiz storage quiz = quizzes[_gameId];
        require(quiz.isActive, "Quiz is not active");
        require(block.timestamp < quiz.startTime + quiz.timeLimit, "Quiz time has expired");
        require(msg.value == ENTRY_FEE, "Incorrect entry fee");
        require(!hasAnswered[_gameId][msg.sender], "Already joined this quiz");
        
        quiz.participants.push(msg.sender);
        quiz.prizePool += msg.value;
        hasAnswered[_gameId][msg.sender] = true;
        
        players[msg.sender].totalGamesPlayed++;
        
        emit PlayerJoined(_gameId, msg.sender);
    }
    
    // Function 3: Submit answer to a quiz
    function submitAnswer(uint256 _gameId, uint256 _answer) external gameExists(_gameId) {
        Quiz storage quiz = quizzes[_gameId];
        require(quiz.isActive, "Quiz is not active");
        require(block.timestamp < quiz.startTime + quiz.timeLimit, "Quiz time has expired");
        require(hasAnswered[_gameId][msg.sender], "Must join quiz first");
        require(playerAnswers[_gameId][msg.sender] == 0 || playerAnswers[_gameId][msg.sender] == _answer, "Answer already submitted");
        require(_answer > 0 && _answer <= 4, "Answer must be between 1-4");
        
        playerAnswers[_gameId][msg.sender] = _answer;
        
        emit AnswerSubmitted(_gameId, msg.sender, _answer);
    }
    
    // Function 4: End quiz and distribute rewards
    function endQuiz(uint256 _gameId) external gameExists(_gameId) {
        Quiz storage quiz = quizzes[_gameId];
        require(quiz.isActive, "Quiz already ended");
        require(
            block.timestamp >= quiz.startTime + quiz.timeLimit || msg.sender == owner,
            "Quiz time not expired or not owner"
        );
        
        quiz.isActive = false;
        
        // Find winners (players who answered correctly)
        address[] memory winners = new address[](quiz.participants.length);
        uint256 winnerCount = 0;
        
        for (uint256 i = 0; i < quiz.participants.length; i++) {
            address participant = quiz.participants[i];
            if (playerAnswers[_gameId][participant] == quiz.correctAnswer + 1) { // +1 because we store 1-4, not 0-3
                winners[winnerCount] = participant;
                winnerCount++;
            }
        }
        
        // Distribute prizes
        if (winnerCount > 0) {
            uint256 prizePerWinner = quiz.prizePool / winnerCount;
            
            for (uint256 i = 0; i < winnerCount; i++) {
                address winner = winners[i];
                players[winner].totalWins++;
                players[winner].totalEarnings += prizePerWinner;
                
                payable(winner).transfer(prizePerWinner);
                
                if (i == 0) { // Set first winner as the main winner for event
                    quiz.winner = winner;
                }
                
                emit QuizEnded(_gameId, winner, prizePerWinner);
            }
        } else {
            // No winners, owner gets the prize pool
            payable(owner).transfer(quiz.prizePool);
            emit QuizEnded(_gameId, address(0), 0);
        }
    }
    
    // Function 5: Get quiz details
    function getQuizDetails(uint256 _gameId) external view gameExists(_gameId) returns (
        string memory question,
        string[] memory options,
        uint256 timeLimit,
        uint256 startTime,
        bool isActive,
        uint256 participantCount,
        uint256 prizePool
    ) {
        Quiz storage quiz = quizzes[_gameId];
        return (
            quiz.question,
            quiz.options,
            quiz.timeLimit,
            quiz.startTime,
            quiz.isActive,
            quiz.participants.length,
            quiz.prizePool
        );
    }
    
    // Utility function to get player stats
    function getPlayerStats(address _player) external view returns (
        uint256 totalGamesPlayed,
        uint256 totalWins,
        uint256 totalEarnings
    ) {
        Player storage player = players[_player];
        return (player.totalGamesPlayed, player.totalWins, player.totalEarnings);
    }
    
    // Emergency withdrawal function for owner
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}
