// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// contract logic (fix)

contract CrypticAscentStaking is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;    
    IERC20 public immutable gameToken;
    uint256 public constant MINIMUM_STAKE = 100 * 10**18; // 100 tokens
    uint256 public constant GAME_FEE_PERCENT = 5; // 5% fee

    struct Game {
        uint256 totalStake;
        uint256 remainingPlayers;
        bool isActive;
        mapping(address => bool) players;
        mapping(address => uint256) playerStakes;
    }

    mapping(uint256 => Game) public games;
    uint256 public nextGameId;

    event GameCreated(uint256 indexed gameId, uint256 playerCount);
    event PlayerStaked(uint256 indexed gameId, address player, uint256 amount);
    event GameStarted(uint256 indexed gameId, uint256 totalStake);
    event PayoutDistributed(uint256 indexed gameId, address[] winners, uint256[] rewards);

    constructor(address _gameToken) Ownable(msg.sender) {
        gameToken = IERC20(_gameToken);
    }

    function createGame(uint256 _playerCount) external onlyOwner whenNotPaused returns (uint256) {
        require(_playerCount >= 2, "Minimum 2 players required");
        uint256 gameId = nextGameId++;
        Game storage game = games[gameId];
        game.remainingPlayers = _playerCount;
        emit GameCreated(gameId, _playerCount);
        return gameId;
    }

    function stake(uint256 _gameId) external nonReentrant whenNotPaused {
        Game storage game = games[_gameId];
        require(!game.isActive, "Game already started");
        require(game.remainingPlayers > 0, "Game is full");
        require(!game.players[msg.sender], "Already staked");

        game.players[msg.sender] = true;
        game.playerStakes[msg.sender] = MINIMUM_STAKE;
        game.totalStake += MINIMUM_STAKE;
        game.remainingPlayers--;

        gameToken.safeTransferFrom(msg.sender, address(this), MINIMUM_STAKE);
        emit PlayerStaked(_gameId, msg.sender, MINIMUM_STAKE);

        if (game.remainingPlayers == 0) {
            game.isActive = true;
            emit GameStarted(_gameId, game.totalStake);
        }
    }

    function distributePayouts(uint256 _gameId, address[] memory _winners, uint256[] memory _scores) external onlyOwner nonReentrant whenNotPaused {
        Game storage game = games[_gameId];
        require(game.isActive, "Game not active");
        require(_winners.length > 0 && _winners.length == _scores.length, "Invalid winners or scores");

        game.isActive = false;
        uint256 totalReward = game.totalStake;
        uint256 gameFee = (totalReward * GAME_FEE_PERCENT) / 100;
        totalReward -= gameFee;

        uint256 totalScore = 0;
        for (uint i = 0; i < _scores.length; i++) {
            totalScore += _scores[i];
        }

        uint256[] memory rewards = new uint256[](_winners.length);
        for (uint i = 0; i < _winners.length; i++) {
            address winner = _winners[i];
            require(game.players[winner], "Invalid winner");
            uint256 reward = (totalReward * _scores[i]) / totalScore;
            gameToken.safeTransfer(winner, reward);
            rewards[i] = reward;
        }

        gameToken.safeTransfer(owner(), gameFee);
        emit PayoutDistributed(_gameId, _winners, rewards);
        delete games[_gameId];
    }

    function getGameInfo(uint256 _gameId) external view returns (uint256 totalStake, uint256 remainingPlayers, bool isActive) {
        Game storage game = games[_gameId];
        return (game.totalStake, game.remainingPlayers, game.isActive);
    }

    function isPlayerInGame(uint256 _gameId, address _player) external view returns (bool) {
        return games[_gameId].players[_player];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawToken(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        _token.safeTransfer(_to, _amount);
    }
}

