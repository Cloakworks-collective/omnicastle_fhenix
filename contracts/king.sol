// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./consts.sol";
import "@fhenixprotocol/contracts/FHE.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract KingOfTheCastle is AccessControl {

    enum Weather {
        CLEAR,
        CLOUDS,
        SNOW,
        RAIN,
        DRIZZLE,
        THUNDERSTORM
    }
	

    struct Army {
        uint32 archers; 
        uint32 infantry;
        uint32 cavalry;
    }

    /* 
    * uint32 is the max value that can be encrypted with FHE
    */
    struct EncryptedArmy {
        euint32 archers;
        euint32 infantry;
        euint32 cavalry;
    }

    struct Castle {
        EncryptedArmy defense;
        address currentKing;
        uint256 lastKingChangedAt;
    }

    struct Player {
        string generalName;
        Army attackingArmy;
        uint32 points;
        uint32 turns;
    }

    struct GameState {
        mapping(address => Player) players;
        uint32 numberOfAttacks;
        Castle castle;
        Weather currentWeather;
    }

    GameState public gameState;
    uint256 public lastTickTock;
    address public immutable owner;
    address[] public playerAddresses;

    bytes32 public constant WEATHERMAN_ROLE = keccak256("WEATHERMAN_ROLE");

    event PlayerJoined(address player, string generalName);
    event ArmyMobilized(address player, uint32 archers, uint32 infantry, uint32 cavalry);
    event AttackLaunched(address attacker, address defender, bool success);
    event DefenseChanged(address king);
    event TurnAdded(address player, uint32 newTurns);
    event WeatherChanged(Weather newWeather);


    constructor() {
        owner = msg.sender;
        lastTickTock = block.timestamp;
        initializeGame();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WEATHERMAN_ROLE, msg.sender);
    }

    function initializeGame() private {

        // Initialize the castle
        // Conversion leak doesnot matter here, everyone knows the initial army size,
        // after the defense set, we need to keep it encrypted
        euint32 encryptedDefaultArmy = FHE.asEuint32(Consts.INITIAL_ARMY_SIZE);
        gameState.castle.defense = EncryptedArmy(encryptedDefaultArmy, encryptedDefaultArmy, encryptedDefaultArmy);
        gameState.castle.currentKing = owner;
        gameState.castle.lastKingChangedAt = block.timestamp;
        gameState.currentWeather = Weather.CLEAR;

        // Initialize the owner as the first player
        // attacking armies are not encrypted, as they are not stored
        gameState.players[owner] = Player("Castle Owner", Army(Consts.INITIAL_ARMY_SIZE, Consts.INITIAL_ARMY_SIZE, Consts.INITIAL_ARMY_SIZE), Consts.INITIAL_POINTS, Consts.INITIAL_TURNS);
        playerAddresses.push(owner);
    }

    // Public functions for the game

    // when a player joins the game, they are given a general name, an initial army, points, and turns
    // the inital values are public and not encrypted
    function joinGame(string memory generalName) external {
        require(bytes(gameState.players[msg.sender].generalName).length == 0, "Player has already joined");
        gameState.players[msg.sender] = Player(
            generalName,
            Army(Consts.INITIAL_ARMY_SIZE, Consts.INITIAL_ARMY_SIZE, Consts.INITIAL_ARMY_SIZE),
            Consts.INITIAL_POINTS,
            Consts.INITIAL_TURNS
        );
        playerAddresses.push(msg.sender);
        emit PlayerJoined(msg.sender, generalName);
    }

    // here the player mobilizes their army, which is not encrypted
    // attacking armies are never encrypted, as the goal is to build up history of attacks
    // and based on public information, the later players can make better decisions
    // the controlled leak of information is a feature of the game
    function mobilize(uint32 archers, uint32 infantry, uint32 cavalry) external {
        Player storage player = gameState.players[msg.sender];
        require(player.turns > 0, "Player has not joined the game");
        require(player.turns >= Consts.TURNS_NEEDED_FOR_MOBILIZE, "Not enough turns");
        require(archers + infantry + cavalry <= Consts.MAX_ATTACK, "Army size exceeds maximum");

        player.attackingArmy = Army(archers, infantry, cavalry);
        player.turns -= Consts.TURNS_NEEDED_FOR_MOBILIZE;

        emit ArmyMobilized(msg.sender, archers, infantry, cavalry);
    }

    // the weatherman can set the weather, which affects the power of the armies
    // function setWeather(Weather newWeather) external onlyRole(WEATHERMAN_ROLE) {
    //     gameState.currentWeather = newWeather;
    //     emit WeatherChanged(newWeather);
    // }

    function setWeather(Weather newWeather) external {
        gameState.currentWeather = newWeather;
        emit WeatherChanged(newWeather);
    }

    function attack() external {
        Player storage attacker = gameState.players[msg.sender];
        require(attacker.turns > 0, "Attacker has not joined the game");
        require(msg.sender != gameState.castle.currentKing, "Current king cannot attack");
        require(attacker.turns >= Consts.TURNS_NEEDED_FOR_ATTACK, "Not enough turns");
        require(block.timestamp >= gameState.castle.lastKingChangedAt + Consts.ATTACK_COOLDOWN, "Castle is under protection");

        // we need to change the attacking army here to encrypted form
        // defense is already encrypted
        EncryptedArmy memory attackingArmy = EncryptedArmy(
            FHE.asEuint32(attacker.attackingArmy.archers), 
            FHE.asEuint32(attacker.attackingArmy.infantry), 
            FHE.asEuint32(attacker.attackingArmy.cavalry)
        );

        bool attackSuccess = calculateBattleOutcome(attackingArmy, gameState.castle.defense);

        if (attackSuccess) {
            gameState.castle.currentKing = msg.sender;
            gameState.castle.lastKingChangedAt = block.timestamp;
            // set the defense with default values
            euint32 encryptedDefaultArmy = FHE.asEuint32(Consts.INITIAL_ARMY_SIZE);
            gameState.castle.defense = EncryptedArmy(
                encryptedDefaultArmy, 
                encryptedDefaultArmy, 
                encryptedDefaultArmy
            );
            attacker.points += Consts.POINTS_FOR_ATTACK_WIN;
        }

        attacker.turns -= Consts.TURNS_NEEDED_FOR_ATTACK;
        gameState.numberOfAttacks++;

        emit AttackLaunched(msg.sender, gameState.castle.currentKing, attackSuccess);
    }


    // this is where the encryption matters, we need to keep the defense encrypted
    // so the cypher text is passed in, and not plain uint32
    // we want to avoid coversion leaks here
    function changeDefense(
        inEuint32 calldata encryptedArchers, 
        inEuint32 calldata encryptedInfantry, 
        inEuint32 calldata encryptedCavalry
        ) external {
        require(msg.sender == gameState.castle.currentKing, "Only the current king can change defense");
        Player storage king = gameState.players[msg.sender];
        require(king.turns >= Consts.TURNS_NEEDED_FOR_CHANGE_DEFENSE, "Not enough turns");

        euint32 enArchers = FHE.asEuint32(encryptedArchers);
        euint32 enInfantry = FHE.asEuint32(encryptedInfantry);
        euint32 enCavalry = FHE.asEuint32(encryptedCavalry);

        // we make sure the total defense is not more than the max defense
        // it is okay to leak that defense follows the game rules.    
        euint32 enTotal = FHE.add(FHE.add(enArchers, enInfantry), enCavalry);
        FHE.req(FHE.eq(enTotal, FHE.asEuint32(Consts.MAX_ATTACK)));

        gameState.castle.defense = EncryptedArmy(enArchers, enInfantry, enCavalry);
        king.turns -= Consts.TURNS_NEEDED_FOR_CHANGE_DEFENSE;

        emit DefenseChanged(msg.sender);
    }

    function tickTock() external {
        require(block.timestamp >= lastTickTock + Consts.TURN_INTERVAL, "Too soon to call tickTock");
        
        for (uint i = 0; i < playerAddresses.length; i++) {
            Player storage player = gameState.players[playerAddresses[i]];
            if (player.turns < Consts.MAX_TURNS) {
                player.turns++;
                emit TurnAdded(playerAddresses[i], player.turns);
            }
        }

        if (gameState.players[gameState.castle.currentKing].points < Consts.MAX_TURNS) {
            gameState.players[gameState.castle.currentKing].points += Consts.POINTS_PER_TURN_FOR_KING;
        }

        lastTickTock = block.timestamp;
    }

    // view functions for the game

    function getPlayerCount() public view returns (uint32) {
        return uint32(playerAddresses.length);
    }

    function getCastle() public view returns (Castle memory) {
        return gameState.castle;
    }

    function getPlayer(address playerAddress) public view returns (Player memory) {
        return gameState.players[playerAddress];
    }

    function getCurrentWeather() public view returns (Weather) {
        return gameState.currentWeather;
    }

    function getNumberOfAttacks() public view returns (uint32) {
        return gameState.numberOfAttacks;
    }

    function getCurrentKing() public view returns (address) {
        return gameState.castle.currentKing;
    }


    // Internal functions for the game
    function calculateBattleOutcome(EncryptedArmy memory attackingArmy, EncryptedArmy memory defendingArmy) private view returns (bool) {
        euint32 attackingPower = calculateAdjustedArmyPower(attackingArmy, gameState.currentWeather);
        euint32 defendingPower = calculateAdjustedArmyPower(defendingArmy, gameState.currentWeather);
        ebool result =  FHE.gt(attackingPower, defendingPower);
        // we want to show decrypted version of the result
        // this is controlled leak of information
        // by looking at public wins and losses, and public attacks, players can make better decisions
        return FHE.decrypt(result);
    }

    // weather effects
    function calculateAdjustedArmyPower(EncryptedArmy memory army, Weather weather) private pure returns (euint32) {
        euint32 archerPower = army.archers;
        euint32 infantryPower = army.infantry;
        euint32 cavalryPower = army.cavalry;

        euint32 effectiveArcherPower;
        euint32 effectiveInfantryPower;
        euint32 effectiveCavalryPower;

        // we need to keep the weather effects encrypted to use them in the calculation
        euint32 enWeather = FHE.asEuint32(uint32(weather));

        // clear weather has no effect

        // if the weather is cloudy
        ebool isCloudy =  enWeather.eq(FHE.asEuint32(uint32(Weather.CLOUDS)));
        effectiveArcherPower = FHE.div(FHE.mul(archerPower, FHE.asEuint32(Consts.ADVANTAGE)), FHE.asEuint32(100));
        archerPower =  FHE.select(isCloudy, effectiveArcherPower, archerPower);
        effectiveCavalryPower = FHE.div(FHE.mul(cavalryPower, FHE.asEuint32(Consts.EXTREME_ADVANTAGE)), FHE.asEuint32(100));
        cavalryPower =  FHE.select(isCloudy, effectiveCavalryPower, cavalryPower);

        // if the weather is snowy
        ebool isSnowy =  enWeather.eq(FHE.asEuint32(uint32(Weather.SNOW)));
        effectiveArcherPower = FHE.div(FHE.mul(archerPower, FHE.asEuint32(Consts.ADVANTAGE)), FHE.asEuint32(100));
        archerPower =  FHE.select(isSnowy, effectiveArcherPower, archerPower);
        effectiveInfantryPower = FHE.div(FHE.mul(infantryPower, FHE.asEuint32(Consts.ADVANTAGE)), FHE.asEuint32(100));
        infantryPower =  FHE.select(isSnowy, effectiveInfantryPower, infantryPower);
        effectiveCavalryPower = FHE.div(FHE.mul(cavalryPower, FHE.asEuint32(Consts.DISADVANTAGE)), FHE.asEuint32(100));
        cavalryPower =  FHE.select(isSnowy, effectiveCavalryPower, cavalryPower);

        // if the weather is rainy
        ebool isRainy =  enWeather.eq(FHE.asEuint32(uint32(Weather.RAIN)));
        effectiveArcherPower = FHE.div(FHE.mul(archerPower, FHE.asEuint32(Consts.DISADVANTAGE)), FHE.asEuint32(100));
        archerPower =  FHE.select(isRainy, effectiveArcherPower, archerPower);
        effectiveInfantryPower = FHE.div(FHE.mul(infantryPower, FHE.asEuint32(Consts.ADVANTAGE)), FHE.asEuint32(100));
        infantryPower =  FHE.select(isRainy, effectiveInfantryPower, infantryPower);
        effectiveCavalryPower = FHE.div(FHE.mul(cavalryPower, FHE.asEuint32(Consts.DISADVANTAGE)), FHE.asEuint32(100));
        cavalryPower =  FHE.select(isRainy, effectiveCavalryPower, cavalryPower);

        // if the weather is drizzle
        ebool isDrizzle =  enWeather.eq(FHE.asEuint32(uint32(Weather.DRIZZLE)));
        effectiveArcherPower = FHE.div(FHE.mul(archerPower, FHE.asEuint32(Consts.ADVANTAGE)), FHE.asEuint32(100));
        archerPower =  FHE.select(isDrizzle, effectiveArcherPower, archerPower);
        effectiveInfantryPower = FHE.div(FHE.mul(infantryPower, FHE.asEuint32(Consts.ADVANTAGE)), FHE.asEuint32(100));
        infantryPower =  FHE.select(isDrizzle, effectiveInfantryPower, infantryPower);

        // if the weather is thunderstorm
        ebool isThunderstorm =  enWeather.eq(FHE.asEuint32(uint32(Weather.THUNDERSTORM)));
        effectiveArcherPower = FHE.div(FHE.mul(archerPower, FHE.asEuint32(Consts.DISADVANTAGE)), FHE.asEuint32(100));
        archerPower =  FHE.select(isThunderstorm, effectiveArcherPower, archerPower);
        effectiveInfantryPower = FHE.div(FHE.mul(infantryPower, FHE.asEuint32(Consts.EXTREME_ADVANTAGE)), FHE.asEuint32(100));
        infantryPower =  FHE.select(isThunderstorm, effectiveInfantryPower, infantryPower);
        effectiveCavalryPower = FHE.div(FHE.mul(cavalryPower, FHE.asEuint32(Consts.EXTREME_DISADVANTAGE)), FHE.asEuint32(100));
        cavalryPower =  FHE.select(isThunderstorm, effectiveCavalryPower, cavalryPower);

        return FHE.add(FHE.add(archerPower, infantryPower), cavalryPower);
    }                      

}